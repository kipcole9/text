defmodule Text.Extract.Url do
  @moduledoc """
  Phase 2 validator for URL candidates.

  Takes a scanner candidate span, applies boundary cleanup, parses the
  URL into RFC 3986 components, and validates each piece against:

  * Twitter-style host-label rules — no leading/trailing dashes,
    underscores allowed only in subdomain labels (not in the
    registrable domain or TLD).

  * UTS #46 IDNA via `Unicode.IDNA.to_ascii/2` — every non-ASCII host
    label must encode to a valid Punycode form. The original Unicode
    form is preserved in `:host`; the all-ASCII form is in
    `:ascii_host`.

  * TLD existence in the bundled IANA list (or the caller-selected
    `:tld_mode`).

  Returns a `%{}` record on success or `{:error, reason}` on rejection.
  """

  alias Text.Extract.{Boundary, Script, Tld, Twitter}

  @typedoc "Parsed URL record."
  @type url_record :: %{
          url: String.t(),
          ascii: String.t(),
          span: {non_neg_integer(), non_neg_integer()},
          scheme: String.t() | nil,
          userinfo: String.t() | nil,
          host: String.t(),
          ascii_host: String.t(),
          port: non_neg_integer() | nil,
          path: String.t() | nil,
          query: String.t() | nil,
          fragment: String.t() | nil
        }

  @typedoc "Reasons for rejecting a URL candidate."
  @type reason ::
          :empty
          | :no_host
          | :invalid_label
          | :invalid_tld
          | :idna_failed
          | :unsupported_scheme
          | :mixed_script
          | :twitter_quirk_rejected

  @default_schemes ~w(http https ftp ftps)

  @doc """
  Validates a URL candidate span.

  ### Arguments

  * `candidate` is the candidate substring as emitted by
    `Text.Extract.Scanner.scan/1`.

  * `span` is the `{start_byte, length_bytes}` tuple positioning
    `candidate` within the original source text — preserved through
    to the returned record's `:span` field.

  ### Options

  * `:require_scheme` — when `true`, only `scheme://…` URLs validate;
    schemeless candidates are rejected. Default `false`.

  * `:schemes` — allowlist of accepted schemes. Default
    `#{inspect(@default_schemes)}`.

  * `:tld_mode` — `:iana` (default) or `:any`. See `Text.Extract.Tld`.

  * `:strict_idn` — when `true`, applies two extra defences against
    homograph attacks: STD3 ASCII rules in the IDNA call (rejects `_`
    in labels), and the UTR #39 §5.1 single-script restriction
    (rejects mixed-script hosts like `аpple.com` where the `а` is
    Cyrillic). Default `false` (matches Twitter behaviour).

  * `:twitter_quirks` — when `true`, applies the Twitter-text-specific
    rules in `Text.Extract.Twitter` (t.co slug max 40 chars, English
    possessive `'s` stripping). Default `false`.

  ### Returns

  * `{:ok, record}` on success.

  * `{:error, reason}` if the candidate fails validation. `record`
    fields are documented in the module docs.
  """
  @spec validate(String.t(), {non_neg_integer(), non_neg_integer()}, keyword()) ::
          {:ok, url_record()} | {:error, reason()}
  def validate(candidate, {start, _len} = _span, options \\ [])
      when is_binary(candidate) do
    raw = Boundary.shrink(candidate)

    if raw == "" do
      {:error, :empty}
    else
      do_validate(raw, {start, byte_size(raw)}, options)
    end
  end

  defp do_validate(raw, span, options) do
    require_scheme = Keyword.get(options, :require_scheme, false)
    schemes = Keyword.get(options, :schemes, @default_schemes)
    tld_mode = Keyword.get(options, :tld_mode, :iana)
    strict = Keyword.get(options, :strict_idn, false)
    quirks? = Keyword.get(options, :twitter_quirks, false)

    with {:ok, parsed} <- parse(raw),
         :ok <- check_scheme(parsed, schemes, require_scheme),
         {:ok, parsed, raw, span} <- truncate_to_tld(parsed, raw, span, tld_mode),
         {:ok, ascii_host} <- idna_host(parsed.host, strict),
         :ok <- check_host_labels(parsed.host),
         :ok <- check_script(parsed.host, strict),
         {:ok, record} <- {:ok, build_record(raw, span, parsed, ascii_host)},
         {:ok, record} <- maybe_twitter_quirks(record, raw, quirks?) do
      {:ok, record}
    end
  end

  defp check_script(_host, false), do: :ok

  defp check_script(host, true) do
    if Script.single_script?(host), do: :ok, else: {:error, :mixed_script}
  end

  defp maybe_twitter_quirks(record, _raw, false), do: {:ok, record}
  defp maybe_twitter_quirks(record, raw, true), do: Twitter.apply({:ok, record}, raw)

  # ---- TLD walk and truncation ----------------------------------------

  # The scanner regex is permissive about the host's last label — it
  # just requires *some* label-shaped token. This function does the
  # TLD validation that used to live inside the regex (as a 7.5KB
  # alternation) and additionally truncates the host when a real TLD
  # appears earlier in the label sequence.
  #
  # For `example.com[Hiragana].comtest`: the regex matches all 3 host
  # labels (and the path). We walk labels right-to-left, asking
  # `Tld.tld?` for each. `comtest` fails, `comだよね` fails, `com`
  # succeeds — host truncates to `example.com` and the trailing
  # `.comtest/path` falls outside the URL.
  defp truncate_to_tld(parsed, raw, span, tld_mode) do
    labels = String.split(parsed.host, ".")
    label_count = length(labels)
    label_pos = find_tld_position(labels, tld_mode)
    mid_pos = find_mid_label_tld(parsed.host, tld_mode)

    cond do
      label_pos == label_count and mid_pos == nil ->
        # Full host already ends in a TLD; no truncation.
        {:ok, parsed, raw, span}

      label_pos == nil and mid_pos == nil ->
        # No TLD anywhere in the host.
        {:error, :invalid_tld}

      true ->
        # Pick the truncation that retains the most of the host. A
        # mid-label TLD always sits *inside* a label, so its byte
        # position is between two label-end positions; comparing on
        # byte offset gives the most-permissive choice.
        label_byte_pos = label_byte_offset(parsed.host, label_pos)
        truncated_host = pick_truncated_host(parsed.host, label_byte_pos, mid_pos)

        truncated_parsed = %{
          parsed
          | host: truncated_host,
            port: nil,
            path: nil,
            query: nil,
            fragment: nil
        }

        truncated_raw = rebuild_raw(truncated_parsed)
        {start, _len} = span
        {:ok, truncated_parsed, truncated_raw, {start, byte_size(truncated_raw)}}
    end
  end

  defp label_byte_offset(_host, nil), do: -1

  defp label_byte_offset(host, label_count) do
    host
    |> String.split(".")
    |> Enum.take(label_count)
    |> Enum.map(&byte_size/1)
    |> Enum.sum()
    |> Kernel.+(label_count - 1)
  end

  defp pick_truncated_host(host, label_pos, nil),
    do: binary_part(host, 0, label_pos)

  defp pick_truncated_host(host, label_pos, mid_pos) do
    pos = max(label_pos, mid_pos)
    binary_part(host, 0, pos)
  end

  # Walks labels right-to-left, returning the count of labels in the
  # longest valid prefix (i.e. the prefix whose last label is a known
  # TLD). Returns `nil` if no label is a TLD or the host has fewer
  # than 2 labels.
  defp find_tld_position(labels, _tld_mode) when length(labels) < 2, do: nil

  defp find_tld_position(labels, tld_mode) do
    count = length(labels)

    Enum.find_value(count..2//-1, fn n ->
      label = Enum.at(labels, n - 1)
      if known_tld?(label, tld_mode), do: n
    end)
  end

  # Mid-label TLD detection for mixed-script labels in scheme URLs.
  #
  # The OLD scanner regex baked in a 7.5 KB alternation of every IANA
  # TLD as the required last label. That alternation, combined with a
  # `(?![A-Za-z0-9_-])` lookahead, meant the regex engine would
  # naturally truncate `example.comだよね.comtest` to `example.com`
  # via backtracking — `comtest` and `comだよね` aren't TLDs but `com`
  # ending right before the Hiragana `だ` is.
  #
  # With the alternation moved out of the regex, full-label truncation
  # alone misses this case. This helper walks the original host
  # string looking for ASCII letter runs that end at a script-boundary
  # (right before a non-ASCII codepoint) and form a known TLD. The
  # latest such position wins.
  #
  # Cheap and safe to skip when the host has no non-ASCII characters
  # — full-label truncation handles the all-ASCII case completely.
  defp find_mid_label_tld(host, tld_mode) do
    if all_ascii?(host) do
      nil
    else
      ~r/[A-Za-z0-9_\-]+/u
      |> Regex.scan(host, return: :index)
      |> Enum.flat_map(fn [{start, len}] ->
        # Must be preceded by `.` (so it's a fresh "label-ish" run, not
        # part of an earlier sub-label) and followed by a non-ASCII
        # character (otherwise it's just a full ASCII label, already
        # handled by `find_tld_position`).
        prev = if start == 0, do: nil, else: :binary.at(host, start - 1)
        next = if start + len < byte_size(host), do: :binary.at(host, start + len), else: nil

        if prev == ?. and next != nil and next >= 0x80 do
          ascii_run = binary_part(host, start, len)
          if known_tld?(ascii_run, tld_mode), do: [start + len], else: []
        else
          []
        end
      end)
      |> case do
        [] -> nil
        positions -> Enum.max(positions)
      end
    end
  end

  defp all_ascii?(<<>>), do: true
  defp all_ascii?(<<byte, rest::binary>>) when byte < 0x80, do: all_ascii?(rest)
  defp all_ascii?(_), do: false

  # A label is a "known TLD" if either its raw form (case-folded) or
  # its IDNA-encoded ASCII form is in the bundled set under `mode`.
  # The IDNA conversion is best-effort — failures fall back to the raw
  # label, which is fine because the IANA list is in lowercase ASCII /
  # `xn--` Punycode and a non-IDNA-convertible label can't match it.
  defp known_tld?(label, mode) do
    cond do
      Tld.tld?(label, mode) ->
        true

      true ->
        case Unicode.IDNA.to_ascii(label) do
          {:ok, ascii} -> Tld.tld?(ascii, mode)
          _ -> false
        end
    end
  end

  defp rebuild_raw(parsed) do
    scheme_part = if parsed.scheme, do: parsed.scheme <> "://", else: ""
    userinfo_part = if parsed.userinfo, do: parsed.userinfo <> "@", else: ""
    port_part = if parsed.port, do: ":" <> Integer.to_string(parsed.port), else: ""
    path_part = parsed.path || ""
    query_part = if parsed.query, do: "?" <> parsed.query, else: ""
    fragment_part = if parsed.fragment, do: "#" <> parsed.fragment, else: ""

    scheme_part <>
      userinfo_part <>
      parsed.host <>
      port_part <>
      path_part <>
      query_part <>
      fragment_part
  end

  # ---- parsing ---------------------------------------------------------

  # Split `raw` into RFC 3986 components: scheme://userinfo@host:port/path?query#fragment.
  # Schemeless inputs (where `raw` does not contain `://`) are accepted
  # — `:scheme` will be `nil` on the parsed result.
  defp parse(raw) do
    {scheme, rest} =
      case String.split(raw, "://", parts: 2) do
        [s, r] ->
          if Regex.match?(~r/\A[A-Za-z][A-Za-z0-9+.\-]*\z/, s) do
            {String.downcase(s), r}
          else
            {nil, raw}
          end

        _ ->
          {nil, raw}
      end

    # Split fragment.
    {body, fragment} =
      case String.split(rest, "#", parts: 2) do
        [b, f] -> {b, f}
        [b] -> {b, nil}
      end

    # Split query.
    {body, query} =
      case String.split(body, "?", parts: 2) do
        [b, q] -> {b, q}
        [b] -> {b, nil}
      end

    # Split path.
    {authority, path} =
      case String.split(body, "/", parts: 2) do
        [a, p] -> {a, "/" <> p}
        [a] -> {a, nil}
      end

    # Split userinfo.
    {userinfo, host_port} =
      case String.split(authority, "@", parts: 2) do
        [u, hp] -> {u, hp}
        [hp] -> {nil, hp}
      end

    # Split port.
    {host, port} =
      case Regex.run(~r/\A(.+?):(\d+)\z/, host_port) do
        [_, h, p] -> {h, String.to_integer(p)}
        _ -> {host_port, nil}
      end

    cond do
      host == "" ->
        {:error, :no_host}

      true ->
        {:ok,
         %{
           scheme: scheme,
           userinfo: userinfo,
           host: host,
           port: port,
           path: path,
           query: query,
           fragment: fragment
         }}
    end
  end

  # ---- scheme check ----------------------------------------------------

  defp check_scheme(%{scheme: nil}, _schemes, true), do: {:error, :unsupported_scheme}
  defp check_scheme(%{scheme: nil}, _schemes, false), do: :ok

  defp check_scheme(%{scheme: scheme}, schemes, _require) do
    if scheme in schemes, do: :ok, else: {:error, :unsupported_scheme}
  end

  # ---- IDNA -----------------------------------------------------------

  # Run the host through UTS #46 ToASCII. ASCII-only hosts pass through
  # unchanged; IDN hosts get Punycoded. Any IDNA failure (DISALLOWED
  # codepoint, hyphen rule violation, oversized label, …) rejects the
  # candidate entirely.
  defp idna_host(host, strict) do
    options = [
      transitional: false,
      check_hyphens: true,
      check_bidi: true,
      check_joiners: true,
      use_std3_ascii_rules: strict
    ]

    case Unicode.IDNA.to_ascii(host, options) do
      {:ok, ascii} -> {:ok, String.downcase(ascii)}
      {:error, _reason} -> {:error, :idna_failed}
    end
  end

  # ---- host label rules -----------------------------------------------

  # Twitter-text rules on the *original* (not-yet-IDNA-encoded) host
  # labels. These are stricter than IDNA in some places (no leading
  # or trailing dashes/underscores) and looser in others (allows `_`
  # in subdomain labels).
  defp check_host_labels(host) do
    labels = String.split(host, ".")
    label_count = length(labels)

    cond do
      label_count < 2 ->
        {:error, :no_host}

      Enum.any?(labels, &(&1 == "")) ->
        {:error, :invalid_label}

      true ->
        labels
        |> Enum.with_index()
        |> Enum.reduce_while(:ok, fn {label, index}, _acc ->
          tld? = index == label_count - 1
          registrable? = index == label_count - 2
          subdomain? = index < label_count - 2

          if valid_label?(label, tld?, registrable?, subdomain?) do
            {:cont, :ok}
          else
            {:halt, {:error, :invalid_label}}
          end
        end)
    end
  end

  defp valid_label?(label, tld?, registrable?, _subdomain?) do
    cond do
      label == "" -> false
      String.length(label) > 63 -> false
      String.starts_with?(label, "-") -> false
      String.ends_with?(label, "-") -> false
      String.starts_with?(label, "_") -> false
      String.ends_with?(label, "_") -> false
      tld? and contains_underscore?(label) -> false
      registrable? and contains_underscore?(label) -> false
      true -> true
    end
  end

  defp contains_underscore?(label), do: String.contains?(label, "_")

  # ---- record builder --------------------------------------------------

  defp build_record(raw, span, parsed, ascii_host) do
    ascii_url = build_ascii_url(parsed, ascii_host)

    %{
      url: raw,
      ascii: ascii_url,
      span: span,
      scheme: parsed.scheme,
      userinfo: parsed.userinfo,
      host: parsed.host,
      ascii_host: ascii_host,
      port: parsed.port,
      path: parsed.path,
      query: parsed.query,
      fragment: parsed.fragment
    }
  end

  defp build_ascii_url(parsed, ascii_host) do
    scheme_part = if parsed.scheme, do: parsed.scheme <> "://", else: ""
    userinfo_part = if parsed.userinfo, do: parsed.userinfo <> "@", else: ""
    port_part = if parsed.port, do: ":" <> Integer.to_string(parsed.port), else: ""
    path_part = parsed.path || ""
    query_part = if parsed.query, do: "?" <> parsed.query, else: ""
    fragment_part = if parsed.fragment, do: "#" <> parsed.fragment, else: ""

    scheme_part <>
      userinfo_part <>
      ascii_host <>
      port_part <>
      path_part <>
      query_part <>
      fragment_part
  end
end
