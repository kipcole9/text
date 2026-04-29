defmodule Text.Clean do
  @moduledoc """
  Text cleanup utilities: HTML stripping, whitespace collapse,
  Unicode normalization, and mojibake repair.

  These are the small, fiddly transforms that every text-processing
  pipeline needs but no single library exposes coherently. The
  `clean/2` function chains them in a sensible default order; the
  individual transforms are also exposed so callers can compose
  their own pipeline.

  ### What each function does

  * `strip_html/1` — removes HTML/XML tags and decodes the most
    common HTML entities.

  * `collapse_whitespace/1` — replaces runs of any whitespace
    (including non-breaking space and other Unicode spaces) with a
    single ASCII space, and trims the ends.

  * `strip_control/1` — removes ASCII and Unicode control
    characters except `\\n`, `\\t`, and `\\r`.

  * `normalize/2` — Unicode normalization. Defaults to NFC.

  * `fix_mojibake/1` — repairs the most common mojibake patterns
    (UTF-8 misinterpreted as Windows-1252 or Latin-1). Inspired by
    `ftfy`. Only handles the well-known cases — not a complete
    replacement for `ftfy`.

  * `clean/2` — applies all of the above in a sensible default
    order. Steps can be turned off via options.

  """

  @entities %{
    "&amp;" => "&",
    "&lt;" => "<",
    "&gt;" => ">",
    "&quot;" => "\"",
    "&apos;" => "'",
    "&nbsp;" => " ",
    "&copy;" => "©",
    "&reg;" => "®",
    "&trade;" => "™",
    "&hellip;" => "…",
    "&mdash;" => "—",
    "&ndash;" => "–",
    "&lsquo;" => "‘",
    "&rsquo;" => "’",
    "&ldquo;" => "“",
    "&rdquo;" => "”",
    "&laquo;" => "«",
    "&raquo;" => "»",
    "&middot;" => "·",
    "&deg;" => "°",
    "&plusmn;" => "±",
    "&times;" => "×",
    "&divide;" => "÷",
    "&para;" => "¶",
    "&sect;" => "§",
    "&bull;" => "•",
    "&dagger;" => "†",
    "&euro;" => "€",
    "&pound;" => "£",
    "&yen;" => "¥",
    "&cent;" => "¢"
  }

  # The most frequent UTF-8-as-Windows-1252 mojibake bytes. Built from
  # the canonical observed-from -> intended-to substitutions.
  @mojibake [
    {"â€™", "’"},
    {"â€˜", "‘"},
    {"â€œ", "“"},
    {"â€¦", "…"},
    {"â€¢", "•"},
    {"Â£", "£"},
    {"Â©", "©"},
    {"Â®", "®"},
    {"Â°", "°"},
    {"Â·", "·"},
    {"Â»", "»"},
    {"Â«", "«"},
    {"Â ", " "},
    {"Ã©", "é"},
    {"Ã¨", "è"},
    {"Ãª", "ê"},
    {"Ã«", "ë"},
    {"Ã ", "à"},
    {"Ã¡", "á"},
    {"Ã¢", "â"},
    {"Ã£", "ã"},
    {"Ã¤", "ä"},
    {"Ã¥", "å"},
    {"Ã­", "í"},
    {"Ã®", "î"},
    {"Ã¯", "ï"},
    {"Ã³", "ó"},
    {"Ã´", "ô"},
    {"Ãµ", "õ"},
    {"Ã¶", "ö"},
    {"Ã¸", "ø"},
    {"Ãº", "ú"},
    {"Ã»", "û"},
    {"Ã¼", "ü"},
    {"Ã¿", "ÿ"},
    {"Ã±", "ñ"},
    {"Ã§", "ç"},
    {"Ã‰", "É"},
    {"Ã€", "À"},
    {"Ã‚", "Â"},
    {"Ãˆ", "È"},
    {"ÃŠ", "Ê"},
    {"ÃŽ", "Î"}
  ]

  @doc """
  Removes HTML/XML tags and decodes common HTML entities.

  This is a pragmatic regex-based stripper, not a security-grade
  HTML parser. Use it for cleaning user input or scraped text, not
  for sanitizing output to a browser.

  ### Arguments

  * `text` is a string that may contain HTML/XML tags and entities.

  ### Returns

  * The text with tags removed and entities decoded.

  ### Examples

      iex> Text.Clean.strip_html("<p>Hello, <b>world</b>!</p>")
      "Hello, world!"

      iex> Text.Clean.strip_html("Tom &amp; Jerry &mdash; cats &amp; mice")
      "Tom & Jerry — cats & mice"

  """
  @spec strip_html(String.t()) :: String.t()
  def strip_html(text) when is_binary(text) do
    text
    |> String.replace(~r/<[^>]*>/, "")
    |> decode_entities()
  end

  defp decode_entities(text) do
    text =
      Enum.reduce(@entities, text, fn {entity, replacement}, acc ->
        String.replace(acc, entity, replacement)
      end)

    # Decode numeric entities &#NNN; and &#xHHH;.
    text
    |> then(
      &Regex.replace(~r/&#(\d+);/, &1, fn _, code ->
        codepoint_to_string(String.to_integer(code))
      end)
    )
    |> then(
      &Regex.replace(~r/&#x([0-9a-fA-F]+);/, &1, fn _, code ->
        codepoint_to_string(String.to_integer(code, 16))
      end)
    )
  end

  defp codepoint_to_string(cp) when cp >= 0 and cp <= 0x10FFFF, do: <<cp::utf8>>
  defp codepoint_to_string(_), do: ""

  @doc """
  Collapses runs of whitespace to single ASCII spaces and trims.

  Recognises Unicode whitespace, not just ASCII — non-breaking
  spaces and ideographic spaces collapse too.

  ### Arguments

  * `text` is the input string.

  ### Returns

  * The text with each run of whitespace replaced by a single space
    and leading/trailing whitespace trimmed.

  ### Examples

      iex> Text.Clean.collapse_whitespace("  hello   world  \\n")
      "hello world"

      iex> Text.Clean.collapse_whitespace("non\\u00A0breaking\\tspaces")
      "non breaking spaces"

  """
  @spec collapse_whitespace(String.t()) :: String.t()
  def collapse_whitespace(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc """
  Removes control characters except `\\n`, `\\t`, and `\\r`.

  ### Arguments

  * `text` is the input string.

  ### Returns

  * The text with non-printable control characters removed.

  ### Examples

      iex> Text.Clean.strip_control("hello\\u0007world")
      "helloworld"

      iex> Text.Clean.strip_control("keep\\nnewlines")
      "keep\\nnewlines"

  """
  @spec strip_control(String.t()) :: String.t()
  def strip_control(text) when is_binary(text) do
    String.replace(text, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
  end

  @doc """
  Applies a Unicode normalization form to the text.

  ### Arguments

  * `text` is the input string.

  * `form` is `:nfc`, `:nfd`, `:nfkc`, or `:nfkd`. The default is
    `:nfc`.

  ### Returns

  * The text in the requested normalization form.

  ### Examples

      iex> e_decomposed = "e" <> <<0x0301::utf8>>
      iex> Text.Clean.normalize(e_decomposed) == "é"
      true

  """
  @spec normalize(String.t(), :nfc | :nfd | :nfkc | :nfkd) :: String.t()
  def normalize(text, form \\ :nfc) when is_binary(text) and form in [:nfc, :nfd, :nfkc, :nfkd] do
    :unicode.characters_to_nfc_binary(text)
    |> apply_form(form, text)
  end

  defp apply_form(_nfc, :nfc, original), do: :unicode.characters_to_nfc_binary(original)
  defp apply_form(_nfc, :nfd, original), do: :unicode.characters_to_nfd_binary(original)
  defp apply_form(_nfc, :nfkc, original), do: :unicode.characters_to_nfkc_binary(original)
  defp apply_form(_nfc, :nfkd, original), do: :unicode.characters_to_nfkd_binary(original)

  @doc """
  Repairs the most common mojibake patterns.

  Mojibake happens when UTF-8 bytes are decoded as Windows-1252 or
  Latin-1, producing strings like `â€™` (a real `’` U+2019 read as
  three single bytes). This function reverses the common cases.

  Only well-known patterns are repaired — for harder cases, use a
  dedicated tool. Output is unchanged if no patterns match.

  ### Arguments

  * `text` is the input string.

  ### Returns

  * The repaired string.

  ### Examples

      iex> Text.Clean.fix_mojibake("itâ€™s working")
      "it’s working"

      iex> Text.Clean.fix_mojibake("café")
      "café"

  """
  @spec fix_mojibake(String.t()) :: String.t()
  def fix_mojibake(text) when is_binary(text) do
    Enum.reduce(@mojibake, text, fn {bad, good}, acc ->
      String.replace(acc, bad, good)
    end)
  end

  @doc """
  Applies the full cleanup pipeline.

  Default order: HTML strip → mojibake fix → control-char strip →
  Unicode normalize (NFC) → whitespace collapse.

  ### Arguments

  * `text` is the input string.

  ### Options

  * `:strip_html` (default `true`) — apply `strip_html/1`.

  * `:fix_mojibake` (default `true`) — apply `fix_mojibake/1`.

  * `:strip_control` (default `true`) — apply `strip_control/1`.

  * `:normalize` (default `:nfc`) — Unicode form to apply, or
    `false` to skip.

  * `:collapse_whitespace` (default `true`) — apply
    `collapse_whitespace/1`.

  ### Returns

  * The cleaned string.

  ### Examples

      iex> Text.Clean.clean("<p>Hello,&nbsp;<b>world</b>!</p>")
      "Hello, world!"

      iex> Text.Clean.clean("itâ€™s   <em>cool</em>")
      "it’s cool"

  """
  @spec clean(String.t(), keyword()) :: String.t()
  def clean(text, options \\ []) when is_binary(text) do
    text
    |> maybe(Keyword.get(options, :strip_html, true), &strip_html/1)
    |> maybe(Keyword.get(options, :fix_mojibake, true), &fix_mojibake/1)
    |> maybe(Keyword.get(options, :strip_control, true), &strip_control/1)
    |> maybe_normalize(Keyword.get(options, :normalize, :nfc))
    |> maybe(Keyword.get(options, :collapse_whitespace, true), &collapse_whitespace/1)
  end

  defp maybe(text, true, fun), do: fun.(text)
  defp maybe(text, false, _fun), do: text

  defp maybe_normalize(text, false), do: text

  defp maybe_normalize(text, form) when form in [:nfc, :nfd, :nfkc, :nfkd],
    do: normalize(text, form)
end
