defmodule Text do
  @moduledoc """
  Functions for basic text processing including:

  * Word counting

  * N-gram generation

  * Pluralization

  * Language detection

  """

  defdelegate ngram(text, n), to: Text.Ngram
  defdelegate detect(text), to: Text.Language

  @doc """
  Pluralize a word.

  ## Arguments

  * `word` is any English word.

  * `options` is a keyword list
    of options.

  ## Options

  * `:mode` is either `:modern` or `:classical`. The
    default is `:modern`.

  * `:language` is the inflection module
    to be used. The default and ony option is
    `Text.Inflect.En`

  ## Returns

  * a `String` representing the pluralized word

  ## Notes

  `mode` when `:classical` applies pluralization
  on latin words used in english but with latin
  suffixes.

  ## Examples

      iex> Text.pluralize "Major general"
      "Major generals"

      iex> Text.pluralize "fish"
      "fish"

      iex> Text.pluralize "soliloquy"
      "soliloquies"

      iex> Text.pluralize "genius", mode: :classical
      "genii"

      iex> Text.pluralize "genius"
      "geniuses"

      iex> Text.pluralize "platypus", mode: :classical
      "platypodes"

      iex> Text.pluralize "platypus"
      "platypuses"

  """
  def pluralize(word, options \\ []) do
    inflector = inflector_from(options)
    mode = Keyword.get(options, :mode, :modern)
    inflector.pluralize(word, mode)
  end

  # Only "en" is supoprted
  defp inflector_from(_options) do
    Text.Inflect.En
  end
end
