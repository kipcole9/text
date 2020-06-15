defmodule Text.Vocabulary.Quadgram do
  @moduledoc """
  An n-gram vocabulary composed
  of quad-grams

  """

  @behaviour Text.Vocabulary

  alias Text.Vocabulary

  @default_ngram 4

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
    @default_ngram..@default_ngram
  end

  def get_vocabulary(language) do
    Vocabulary.get_vocabulary(language, __MODULE__)
  end

  def file do
    Path.join(:code.priv_dir(:text), "vocabulary/udhr_quadgram.etf")
  end

  def calculate_ngrams(text) do
    Vocabulary.calculate_ngrams(text, ngram_range())
  end

end