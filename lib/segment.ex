defmodule Text.Segment do
  @moduledoc """
  Locale-aware word and sentence segmentation.

  Implements the public surface area you reach for when you want to
  break a string into its semantic pieces — words or sentences —
  following the Unicode segmentation rules in
  [UAX #29 (Text Segmentation)](https://unicode.org/reports/tr29/).
  Line-break segmentation (UAX #14) is available via `stream/2` for
  the small set of callers who need it.

  This module is a thin facade over the
  [`unicode_string`](https://hex.pm/packages/unicode_string) package,
  exposed under the `Text` namespace so callers don't have to know
  where the underlying primitives live. Two adjustments over the raw
  `Unicode.String.split/2`:

  * **`words/2`** drops punctuation tokens by default. The Unicode word
    segmentation algorithm treats `","` and `"!"` as words just like
    `"hello"`; in practice every text-processing pipeline immediately
    filters those out, so this module does it by default.

  * **`sentences/2`** trims trailing whitespace from each sentence so
    callers don't have to. The Unicode rules attach trailing whitespace
    to the preceding sentence, which is rarely what you want.

  Pass `punctuation: :keep` or `trim: false` to opt back in to the raw
  Unicode behaviour.

  ### Locale-awareness and abbreviation suppressions

  Word and sentence segmentation rules differ across languages —
  German treats `"Donaudampfschiffahrtsgesellschaft"` as one word,
  Japanese needs dictionary-based segmentation for any meaningful
  tokenisation, and Thai has no spaces at all. Pass `locale: "ja"`,
  `locale: "th"`, etc., to pick up those tailorings; without a locale
  option the default Unicode rules apply.

  When a locale is supplied, `sentences/2` also applies CLDR's
  *suppression* list for that locale by default, which keeps common
  abbreviations like `"i.e."` and `"e.g."` from being treated as
  sentence terminators. The list is partial — it covers the most
  common forms but not every abbreviation in use — so callers needing
  comprehensive abbreviation handling should still layer their own
  rules on top. Pass `suppressions: false` to opt out of even the
  default list.

  ### Streaming

  For very large inputs (log files, full books) prefer `stream/2`,
  which returns a lazy `Stream` rather than realising the entire token
  list in memory.

  """

  @typedoc "A segmentation break type understood by Unicode UAX #29."
  @type break :: :word | :sentence | :line | :grapheme

  @doc """
  Splits `text` into word tokens, dropping whitespace and punctuation
  by default.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  * `:punctuation` — `:drop` (default) or `:keep`. Whether to include
    word-typed punctuation tokens (`","`, `"!"`, `"?"`, etc.) in the
    output.

  * `:locale` — a BCP-47 locale string (`"en"`, `"ja"`, ...). When
    given, locale-specific break rules from CLDR are applied. Defaults
    to the Unicode root locale rules.

  ### Returns

  * A list of strings.

  ### Examples

      iex> Text.Segment.words("Hello, world! How are you?")
      ["Hello", "world", "How", "are", "you"]

      iex> Text.Segment.words("Hello, world!", punctuation: :keep)
      ["Hello", ",", "world", "!"]

      iex> Text.Segment.words("naïve café")
      ["naïve", "café"]

      iex> Text.Segment.words("")
      []

  """
  @spec words(String.t(), keyword()) :: [String.t()]
  def words(text, options \\ []) when is_binary(text) do
    punctuation = Keyword.get(options, :punctuation, :drop)
    locale = Keyword.get(options, :locale)

    split_options = [break: :word, trim: true] ++ locale_option(locale)

    text
    |> Unicode.String.split(split_options)
    |> filter_punctuation(punctuation)
  end

  defp filter_punctuation(tokens, :keep), do: tokens

  defp filter_punctuation(tokens, :drop) do
    Enum.reject(tokens, &punctuation_only?/1)
  end

  # A token is "punctuation only" if every grapheme in it falls into a
  # Unicode punctuation or symbol category. We don't have direct access
  # to the category from `unicode_string`, but `Regex` covers the same
  # ground via `\p{P}` and `\p{S}`.
  defp punctuation_only?(""), do: true

  defp punctuation_only?(token) do
    Regex.match?(~r/^[\p{P}\p{S}]+$/u, token)
  end

  defp locale_option(nil), do: []
  defp locale_option(locale), do: [locale: locale]

  @doc """
  Splits `text` into sentences, trimming trailing whitespace by default.

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  * `:trim` — `true` (default) trims leading and trailing whitespace
    from each sentence. `false` preserves the raw Unicode-segmentation
    output where the trailing whitespace before the next sentence is
    attached to the preceding sentence.

  * `:locale` — a BCP-47 locale string. When given, locale-specific
    sentence break rules from CLDR are applied. Also enables CLDR's
    abbreviation suppression list (see `:suppressions`).

  * `:suppressions` — `true` (default) applies CLDR's per-locale
    abbreviation suppression list, which prevents common forms like
    `"i.e."` and `"e.g."` from being treated as sentence terminators.
    Has no effect when `:locale` is not set.

  ### Returns

  * A list of strings.

  ### Examples

      iex> Text.Segment.sentences("Hello, world! How are you?")
      ["Hello, world!", "How are you?"]

      iex> Text.Segment.sentences("First. Second! Third? Yes.")
      ["First.", "Second!", "Third?", "Yes."]

      iex> Text.Segment.sentences("Hello, world! How are you?", trim: false)
      ["Hello, world! ", "How are you?"]

      iex> Text.Segment.sentences("He used i.e. and e.g. in his memo. Then stopped.", locale: "en")
      ["He used i.e. and e.g. in his memo.", "Then stopped."]

      iex> Text.Segment.sentences("")
      []

  """
  @spec sentences(String.t(), keyword()) :: [String.t()]
  def sentences(text, options \\ []) when is_binary(text) do
    trim? = Keyword.get(options, :trim, true)
    locale = Keyword.get(options, :locale)
    suppressions? = Keyword.get(options, :suppressions, true)

    split_options =
      [break: :sentence, trim: true] ++
        locale_option(locale) ++
        [suppressions: suppressions?]

    raw = Unicode.String.split(text, split_options)

    if trim? do
      Enum.map(raw, &String.trim/1)
    else
      raw
    end
  end

  @doc """
  Returns a `Stream` that lazily yields segments of `text`.

  Use this for inputs large enough that materialising the entire token
  list at once would be wasteful. The `:break` option chooses the
  segmentation level (`:word`, `:sentence`, `:line`, or `:grapheme`).

  ### Arguments

  * `text` is a UTF-8 string.

  ### Options

  * `:break` — required. One of `:word`, `:sentence`, `:line`, or
    `:grapheme`.

  * `:trim` — defaults to `true`. Drops whitespace-only tokens.

  * `:locale` — a BCP-47 locale string.

  ### Returns

  * A `Stream`.

  ### Examples

      iex> Text.Segment.stream("Hello world", break: :word) |> Enum.to_list()
      ["Hello", "world"]

  """
  @spec stream(String.t(), keyword()) :: Enumerable.t()
  def stream(text, options) when is_binary(text) do
    break = Keyword.fetch!(options, :break)
    trim? = Keyword.get(options, :trim, true)
    locale = Keyword.get(options, :locale)

    Unicode.String.stream(
      text,
      [break: break, trim: trim?] ++ locale_option(locale)
    )
  end
end
