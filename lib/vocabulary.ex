defmodule Text.Vocabulary do
  alias Text.Ngram
  alias Text.Language.Udhr

  @callback build_vocabulary() :: map()
  @callback get_vocabulary() :: map()

  def get_vocabulary(language, vocabulary_module) do
    if is_nil(:persistent_term.get({vocabulary_module, language}, nil)) do
      load_vocabulary!(vocabulary_module)
    end
    :persistent_term.get({vocabulary_module, language}, nil)
  end

  def load_vocabulary!(vocabulary_module) do
    IO.puts "Loading vocabulary #{vocabulary_module}"
    vocabulary =
      vocabulary_module.file
      |> File.read!
      |> :erlang.binary_to_term

    for {language, ngrams} <- vocabulary do
      :persistent_term.put({vocabulary_module, language}, ngrams)
    end
  end

  def top_n(vocabulary, n \\ 10) do
    vocabulary
    |> Enum.filter(fn {_ngram, [rank, _probability]} -> rank < n end)
    |> Enum.sort_by(fn {_ngram, [rank, _probability]} -> rank end)
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

  def calculate_ngrams({language, entry}, range) do
    ngrams =
      entry
      |> Udhr.udhr_corpus_content
      |> calculate_ngrams(range)

    {language, ngrams}
  end

  def calculate_ngrams(content, range) when is_binary(content) do
    content
    |> get_ngrams(range)
    |> convert_to_probabilities()
    |> order_for_ranking()
    |> Enum.with_index
    |> Enum.map(fn {{ngram, probability}, index} -> {ngram, [index, probability]} end)
    |> Map.new
  end

  def order_for_ranking(ngrams) do
    Enum.sort(ngrams, fn
      {ngram1, score}, {ngram2, score} -> ngram2 > ngram1
      {_ngram1, score1}, {_ngram2, score2} -> score2 > score1
    end)
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