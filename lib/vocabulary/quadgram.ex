defmodule Text.Vocabulary.Quadgram do
  import Text.Language
  import Text.Vocabulary
  import Text.Language.Udhr

  @default_ngram 4

  def build_vocabulary do
    vocabulary =
      udhr_corpus()
      |> Task.async_stream(__MODULE__, :calculate_ngrams, [@default_ngram..@default_ngram], async_options())
      |> Enum.map(&elem(&1, 1))
      |> Map.new

    binary = :erlang.term_to_binary(vocabulary)
    :ok = File.write!(udhr_corpus_quadgram_file(), binary)
    vocabulary
  end

  def get_vocabulary(language) do
    Text.Vocabulary.get_vocabulary(language, __MODULE__, udhr_corpus_quadgram_file())
  end

  def udhr_corpus_quadgram_file do
    Path.join(:code.priv_dir(:text), "vocabulary/udhr_quadgram.etf")
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

end