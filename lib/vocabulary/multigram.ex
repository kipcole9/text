defmodule Text.Vocabulary.Multigram do
  alias Text.Ngram
  import Text.Language
  import Text.Language.Udhr

  def build_vocabulary do
    vocabulary =
      udhr_corpus()
      |> Task.async_stream(__MODULE__, :calculate_ngrams, [2..4], async_options())
      |> Enum.map(&elem(&1, 1))
      |> Map.new

    binary = :erlang.term_to_binary(vocabulary)
    :ok = File.write!(udhr_corpus_multigram_file(), binary)
    vocabulary
  end

  def get_vocabulary(language) do
    Text.Vocabulary.get_vocabulary(language, __MODULE__, udhr_corpus_multigram_file())
  end

  def udhr_corpus_multigram_file do
    Path.join(:code.priv_dir(:text), "vocabulary/udhr_multigram.etf")
  end

  def calculate_ngrams({language, entry}, range) do
    ngrams =
      entry
      |> udhr_corpus_content
      |> calculate_ngrams(range)

    {language, ngrams}
  end

  def calculate_ngrams(content, range) when is_binary(content) do
    content
    |> get_ngrams(range)
    |> convert_to_probabilities()
    |> Enum.sort(fn {_ngram1, prob1}, {_ngram2, prob2} -> prob1 > prob2 end)
    |> Enum.with_index
    |> Enum.map(fn {{ngram, probability}, index} -> {ngram, [index, probability]} end)
    |> Map.new
  end

  def get_ngrams(content, from..to) do
    for n <- from..to do
      Ngram.ngram(content, n)
    end
    |> merge_maps
  end

  def merge_maps([a]) do
    a
  end

  def merge_maps([a, b]) do
    Map.merge(a, b)
  end

  def merge_maps([a, b | rest]) do
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