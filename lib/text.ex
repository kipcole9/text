defmodule Text do
  @moduledoc """
  Functions for basic text processing

  """

  defdelegate ngram(text, n), to: Text.Ngram
  defdelegate detect_language(text), to: Text.Detect
  defdelegate pluralize(word, mode), to: Text.Inflect.En
  defdelegate pluralize(word), to: Text.Inflect.En

end
