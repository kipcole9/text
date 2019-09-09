defmodule Text.Vocabulary do
  @callback build_vocabulary() :: map()
  @callback get_vocabulary() :: map()

  def get_vocabulary(language, vocabulary_module, vocabulary_file) do
    if is_nil(:persistent_term.get({vocabulary_module, language}, nil)) do
      vocabulary =
        vocabulary_file
        |> File.read!
        |> :erlang.binary_to_term

      for {language, ngrams} <- vocabulary do
        :persistent_term.put({vocabulary_module, language}, ngrams)
      end
    end
    :persistent_term.get({vocabulary_module, language}, nil)
  end
end