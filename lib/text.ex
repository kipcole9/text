defmodule Text do
  @moduledoc """
  Documentation for LangDetect.
  """

  defdelegate ngram(text, n), to: Text.Ngram
  defdelegate detect_language(text), to: Text.Language, as: :detect

end
