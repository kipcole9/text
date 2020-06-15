defmodule Text.Vocabulary.Multigram do
  @moduledoc """
  An n-gram vocabulary composed
  of n-grams ranging from 2 to 4
  characters in length

  """

  @behaviour Text.Vocabulary

  alias Text.Vocabulary

  @ngram_range 2..4

  if Code.ensure_loaded?(Text.Language.Udhr) do
    def build_vocabulary do
      import Text.Language.Udhr
      import Text.Language

      vocabulary =
        udhr_corpus()
        |> Task.async_stream(Vocabulary, :calculate_ngrams, [ngram_range()], async_options())
        |> Enum.map(&elem(&1, 1))
        |> Map.new

      binary = :erlang.term_to_binary(vocabulary)
      :ok = File.write!(file(), binary)
      vocabulary
    end
  end

  def load_vocabulary! do
    Vocabulary.load_vocabulary!(__MODULE__)
  end

  def ngram_range do
    @ngram_range
  end

  def get_vocabulary(language) do
    Text.Vocabulary.get_vocabulary(language, __MODULE__)
  end

  def file do
    Path.join(:code.priv_dir(:text), "vocabulary/udhr_multigram.etf")
  end

  def calculate_ngrams(text) do
    Vocabulary.calculate_ngrams(text, ngram_range())
  end

end