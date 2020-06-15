defmodule Text.Vocabulary.Bigram do
  @moduledoc """
  An n-gram vocabulary composed
  of bi-grams

  """

  @behaviour Text.Vocabulary

  alias Text.Vocabulary
  import Text.Language
  import Text.Language.Udhr

  @default_ngram 2

  def build_vocabulary do
    vocabulary =
      udhr_corpus()
      |> Task.async_stream(Vocabulary, :calculate_ngrams, [ngram_range()], async_options())
      |> Enum.map(&elem(&1, 1))
      |> Map.new

    binary = :erlang.term_to_binary(vocabulary)
    :ok = File.write!(file(), binary)
    vocabulary
  end

  def load_vocabulary! do
    Vocabulary.load_vocabulary!(__MODULE__)
  end

  def ngram_range do
    @default_ngram..@default_ngram
  end

  def get_vocabulary(language) do
    Vocabulary.get_vocabulary(language, __MODULE__)
  end

  def file do
    Path.join(:code.priv_dir(:text), "vocabulary/udhr_bigram.etf")
  end

  def calculate_ngrams(text) do
    Vocabulary.calculate_ngrams(text, ngram_range())
  end

end