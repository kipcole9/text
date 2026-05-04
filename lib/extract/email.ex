defmodule Text.Extract.Email do
  @moduledoc """
  Phase 2 validator for email-address candidates.

  Takes a scanner candidate span and validates it as an email address
  per RFC 5322 §3.4.1 (dot-atom local part) and RFC 6531 (SMTPUTF8 /
  EAI — internationalised local parts) when the `:eai` option is on.

  The host part is validated identically to URL hosts: per-label IDNA
  via `Unicode.IDNA.to_ascii/2`, then TLD lookup against the bundled
  IANA list.

  Returns a structured `%{}` record on success or `{:error, reason}` on
  rejection.
  """

  alias Text.Extract.{Boundary, Tld}

  @typedoc "Parsed email record."
  @type email_record :: %{
          email: String.t(),
          ascii: String.t(),
          span: {non_neg_integer(), non_neg_integer()},
          local: String.t(),
          host: String.t(),
          ascii_host: String.t()
        }

  @typedoc "Reasons for rejecting an email candidate."
  @type reason ::
          :empty
          | :no_local
          | :no_host
          | :invalid_local
          | :invalid_host
          | :idna_failed
          | :invalid_tld

  # RFC 5322 atext (excluding `@` and `.` which are structural). EAI
  # mode (RFC 6531) additionally accepts any non-ASCII codepoint.
  @atext_ascii ~c"!#$%&'*+-/=?^_`{|}~" ++
                 Enum.to_list(?A..?Z) ++
                 Enum.to_list(?a..?z) ++
                 Enum.to_list(?0..?9)

  @doc """
  Validates an email candidate span.

  ### Arguments

  * `candidate` is the candidate substring as emitted by
    `Text.Extract.Scanner.scan/1`.

  * `span` is the `{start_byte, length_bytes}` tuple positioning
    `candidate` within the original source text — preserved through
    to the returned record's `:span` field.

  ### Options

  * `:eai` — when `true`, allow non-ASCII codepoints in the local part
    per RFC 6531 SMTPUTF8. Default `true`.

  * `:tld_mode` — `:iana` (default) or `:any`.

  * `:strict_idn` — when `true`, IDNA uses STD3 ASCII rules. Default
    `false`.

  ### Returns

  * `{:ok, record}` on success.

  * `{:error, reason}` on rejection.
  """
  @spec validate(String.t(), {non_neg_integer(), non_neg_integer()}, keyword()) ::
          {:ok, email_record()} | {:error, reason()}
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
    eai? = Keyword.get(options, :eai, true)
    tld_mode = Keyword.get(options, :tld_mode, :iana)
    strict = Keyword.get(options, :strict_idn, false)

    with [local, host] <- split_at_at(raw),
         :ok <- check_local(local, eai?),
         :ok <- check_host(host),
         {:ok, ascii_host} <- idna_host(host, strict),
         :ok <- check_tld(ascii_host, tld_mode) do
      {:ok,
       %{
         email: raw,
         ascii: local <> "@" <> ascii_host,
         span: span,
         local: local,
         host: host,
         ascii_host: ascii_host
       }}
    else
      :error -> {:error, :no_local}
      {:error, _} = err -> err
    end
  end

  # RFC 5322 / 6531: an email address is `local-part "@" domain`. We
  # split on the *last* `@` to allow `@` in the local part (quoted-
  # string form, which we do not otherwise validate but should not
  # mis-split).
  defp split_at_at(raw) do
    case String.split(raw, "@") do
      [_one] -> :error
      parts -> [List.last(parts) | Enum.reverse(tl(Enum.reverse(parts)))] |> case do
        [host | local_parts] -> [Enum.reverse(local_parts) |> Enum.join("@"), host]
      end
    end
  end

  # RFC 5322 dot-atom: 1*atext *("." 1*atext) — at least one atext
  # char, optionally followed by `.`-separated runs of atext. RFC 6531
  # extends `atext` to include any non-ASCII codepoint.
  defp check_local("", _eai), do: {:error, :no_local}

  defp check_local(local, eai?) do
    parts = String.split(local, ".")

    cond do
      Enum.any?(parts, &(&1 == "")) -> {:error, :invalid_local}
      Enum.all?(parts, &valid_atext?(&1, eai?)) -> :ok
      true -> {:error, :invalid_local}
    end
  end

  defp valid_atext?(<<>>, _eai), do: false

  defp valid_atext?(part, eai?) do
    part
    |> String.to_charlist()
    |> Enum.all?(fn c ->
      cond do
        c in @atext_ascii -> true
        eai? and c >= 0x80 -> true
        true -> false
      end
    end)
  end

  defp check_host(""), do: {:error, :no_host}

  defp check_host(host) do
    labels = String.split(host, ".")

    cond do
      length(labels) < 2 -> {:error, :no_host}
      Enum.any?(labels, &(&1 == "")) -> {:error, :invalid_host}
      Enum.any?(labels, &(String.starts_with?(&1, "-") or String.ends_with?(&1, "-"))) ->
        {:error, :invalid_host}
      true -> :ok
    end
  end

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
      {:error, _} -> {:error, :idna_failed}
    end
  end

  defp check_tld(ascii_host, mode) do
    tld = ascii_host |> String.split(".") |> List.last()
    if Tld.tld?(tld, mode), do: :ok, else: {:error, :invalid_tld}
  end
end
