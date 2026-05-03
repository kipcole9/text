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

  alias Text.Extract.{Boundary, Tld}

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

  @default_schemes ~w(http https ftp ftps)

  @doc """
  Validates a URL candidate span.

  ### Arguments

  * `text` is the original UTF-8 source string.

  * `span` is a `{start_byte, length_bytes}` tuple from the scanner.

  ### Options

  * `:require_scheme` — when `true`, only `scheme://…` URLs validate;
    schemeless candidates are rejected. Default `false`.

  * `:schemes` — allowlist of accepted schemes. Default
    `#{inspect(@default_schemes)}`.

  * `:tld_mode` — `:iana` (default) or `:any`. See `Text.Extract.Tld`.

  * `:strict_idn` — when `true`, the IDNA call uses STD3 ASCII rules
    (rejects `_` in labels). Default `false` (matches Twitter, allows
    `_` in subdomain labels).

  ### Returns

  * `{:ok, record}` on success.

  * `{:error, reason}` if the candidate fails validation. `record`
    fields are documented in the module docs.
  """
  @spec validate(String.t(), {non_neg_integer(), non_neg_integer()}, keyword()) ::
          {:ok, url_record()} | {:error, reason()}
  def validate(text, {start, len}, options \\ []) when is_binary(text) do
    {start, len} = Boundary.shrink(text, {start, len})

    if len == 0 do
      {:error, :empty}
    else
      raw = :binary.part(text, start, len)
      do_validate(raw, {start, len}, options)
    end
  end

  defp do_validate(raw, span, options) do
    require_scheme = Keyword.get(options, :require_scheme, false)
    schemes = Keyword.get(options, :schemes, @default_schemes)
    tld_mode = Keyword.get(options, :tld_mode, :iana)
    strict = Keyword.get(options, :strict_idn, false)

    with {:ok, parsed} <- parse(raw),
         :ok <- check_scheme(parsed, schemes, require_scheme),
         {:ok, ascii_host} <- idna_host(parsed.host, strict),
         :ok <- check_host_labels(parsed.host),
         :ok <- check_tld(ascii_host, tld_mode) do
      {:ok, build_record(raw, span, parsed, ascii_host)}
    end
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

  # ---- TLD check -------------------------------------------------------

  defp check_tld(ascii_host, mode) do
    tld =
      ascii_host
      |> String.split(".")
      |> List.last()

    if Tld.tld?(tld, mode), do: :ok, else: {:error, :invalid_tld}
  end

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
