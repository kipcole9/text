defmodule Text.Vocabulary do
  alias Text.Ngram
  alias Text.Language.Udhr

  @callback build_vocabulary() :: map()
  @callback get_vocabulary() :: map()
  @callback file() :: String.t()

  @known_vocabularies [
    Text.Vocabulary.Quadgram,
    Text.Vocabulary.Bigram,
    Text.Vocabulary.Multigram
  ]

  @known_languages Text.Language.Udhr.known_languages()

  @max_ngrams 300

  def known_vocabularies do
    @known_vocabularies
  end

  def build_vocabularies do
    @known_vocabularies
    |> Enum.each(&(&1.build_vocabulary/0))
  end

  def get_vocabulary(language, vocabulary_module) do
    :persistent_term.get({vocabulary_module, language}, nil)
  end

  def load_vocabulary!(vocabulary_module) do
    vocabulary =
      vocabulary_module.file
      |> File.read!
      |> :erlang.binary_to_term

    for {language, ngrams} <- vocabulary do
      :persistent_term.put({vocabulary_module, language}, ngrams)
    end

    :persistent_term.put({vocabulary_module, :languages}, Map.keys(vocabulary))
    vocabulary
  end

  def top_n(vocabulary, language, n)
      when vocabulary in @known_vocabularies and language in @known_languages do
    vocabulary.file
    |> File.read!
    |> :erlang.binary_to_term
    |> Map.fetch!(language)
    |> top_n(n)
  end

  def top_n(vocabulary, n \\ @max_ngrams) do
    vocabulary
    |> Enum.sort(fn {_ngram1, [rank1, _probability1]}, {_ngram2, [rank2, _probability2]} ->
      rank1 < rank2
    end)
    |> Enum.take(n)
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

  def calculate_ngrams(content, range, top_n \\ 300) when is_binary(content) do
    content
    |> get_ngrams(range)
    |> convert_to_probabilities()
    |> order_for_ranking()
    |> Enum.with_index(1)
    |> Enum.map(fn {{ngram, probability}, index} -> {ngram, [index, probability]} end)
    |> top_n(top_n)
    |> Map.new
  end

  def order_for_ranking(ngrams) do
    Enum.sort(ngrams, fn
      {ngram1, score}, {ngram2, score} -> ngram1 > ngram2
      {_ngram1, score1}, {_ngram2, score2} -> score1 > score2
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