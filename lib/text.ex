defmodule Text do
  @moduledoc """
  Functions for basic text processing

  """

  defdelegate ngram(text, n), to: Text.Ngram
  defdelegate detect(text), to: Text.Language
  defdelegate pluralize(word, mode), to: Text.Inflect.En
  defdelegate pluralize(word), to: Text.Inflect.En

end
