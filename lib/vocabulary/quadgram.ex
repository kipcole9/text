defmodule Text.Vocabulary.Quadgram do
  alias Text.Ngram
  import Text.Language
  import Text.Language.Udhr

  @default_ngram 4

  def build_vocabulary do
    vocabulary =
      udhr_corpus()
      |> Task.async_stream(__MODULE__, :process_corpus_entry, [], async_options())
      |> Enum.map(&elem(&1, 1))
      |> Map.new
      |> :erlang.term_to_binary

    :ok = File.write!(udhr_corpus_quadgram_file(), vocabulary)
    :persistent_term.put(:quadgram, vocabulary)
    vocabulary
  end

  def get_vocabulary do
    if is_nil(:persistent_term.get(:quadgram, nil)) do
      vocabulary =
        udhr_corpus_quadgram_file()
        |> File.read!
        |> :erlang.binary_to_term

      for {language, quadgrams} <- vocabulary do
        :persistent_term.put({__MODULE__, language}, quadgrams)
      end
    end
    __MODULE__
  end

  def udhr_corpus_quadgram_file do
    Path.join(:code.priv_dir(:text), "vocabulary/udhr_quadgram.etf")
  end

  def process_corpus_entry({language, entry}, n \\ @default_ngram) do
    ngrams =
      entry
      |> udhr_corpus_content
      |> Ngram.ngram(n)
      |> convert_to_probabilities()
      |> Enum.with_index
      |> Enum.map(fn {{ngram, probability}, index} -> {ngram, [index, probability]} end)
      |> Map.new

    {language, ngrams}
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