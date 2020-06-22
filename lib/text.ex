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
  defdelegate detect(text, options), to: Text.Language

  @doc """
  Pluralize a noun.

  ## Arguments

  * `word` is any English noun.

  * `options` is a keyword list
    of options.

  ## Options

  * `:mode` is either `:modern` or `:classical`. The
    default is `:modern`.

  * `:language` is the inflection module
    to be used. The default and ony option is
    `Text.Inflect.En`

  ## Returns

  * a `String` representing the pluralized noun

  ## Notes

  `mode` when `:classical` applies pluralization
  on latin nouns used in english but with latin
  suffixes.

  ## Examples

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

  # Only "en" is supoprted
  defp inflector_from(_options) do
    Text.Inflect.En
  end

  @doc false
  def ensure_compiled?(module) do
    case Code.ensure_compiled(module) do
      {:module, _module} -> true
      _other -> false
    end
  end
end
