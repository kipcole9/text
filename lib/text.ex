defmodule Text do
  @moduledoc """
  Text and language processing for Elixir.

  This is the library's entry-point module. It exposes two convenience
  functions — `ngram/2` (delegated to `Text.Ngram`) for n-gram
  generation and `pluralize_noun/2` for English pluralisation — while
  the bulk of the functionality lives in focused submodules:

  * `Text.Language`, `Text.Language.Classifier.Fasttext` — language
    identification.

  * `Text.Sentiment`, `Text.POS`, `Text.NER` — sentiment, part-of-speech
    tagging, and named-entity recognition.

  * `Text.Extract`, `Text.PII`, `Text.Clean`, `Text.Slug` — extraction,
    redaction, and normalisation.

  * `Text.Distance`, `Text.Similarity`, `Text.Phonetic.*` — string and
    phonetic comparison.

  * `Text.Ngram`, `Text.IR`, `Text.WordCloud`, `Text.Summarize` —
    statistics, search, and summarisation.

  See the README and guides for a capability overview.

  """
  @typedoc "A language as a BCP-47 string"
  @type language :: String.t()

  defdelegate ngram(text, n), to: Text.Ngram

  @doc """
  Pluralize a noun.

  ### Arguments

  * `word` is any English noun.

  * `options` is a keyword list
    of options.

  ### Options

  * `:mode` is either `:modern` or `:classical`. The
    default is `:modern`.

  * `:language` is the inflection module
    to be used. The default and only option is
    `Text.Inflect.En`.

  ### Returns

  * A `String` representing the pluralized noun.

  ### Notes

  `mode` when `:classical` applies pluralization
  on latin nouns used in english but with latin
  suffixes.

  ### Examples

      iex> Text.pluralize_noun "Major general"
      "Major generals"

      iex> Text.pluralize_noun "fish"
      "fish"

      iex> Text.pluralize_noun "soliloquy"
      "soliloquies"

      iex> Text.pluralize_noun "genius", mode: :classical
      "genii"

      iex> Text.pluralize_noun "genius"
      "geniuses"

      iex> Text.pluralize_noun "platypus", mode: :classical
      "platypodes"

      iex> Text.pluralize_noun "platypus"
      "platypuses"

  """
  def pluralize_noun(word, options \\ []) do
    inflector = inflector_from(options)
    mode = Keyword.get(options, :mode, :modern)
    inflector.pluralize_noun(word, mode)
  end

  # Only "en" is supported
  defp inflector_from(_options) do
    Text.Inflect.En
  end
end
