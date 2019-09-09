defmodule Text.Vocabulary do
  alias Text.Ngram

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

  def get_ngrams(content, from..to) do
    for n <- from..to do
      Ngram.ngram(content, n)
    end
    |> merge_maps
  end

  defp merge_maps([a]) do
    a
  end

  defp merge_maps([a, b]) do
    Map.merge(a, b)
  end

  defp merge_maps([a, b | rest]) do
    merge_maps([Map.merge(a, b) | rest])
  end

  def convert_to_probabilities(ngrams) do
    sum =
      ngrams
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum

    ngrams
    |> Enum.map(fn {ngram, count} ->
      {ngram, :math.log(count / sum)}
    end)
  end

end