defmodule Text.Vocabulary.Multigram do
  import Text.Language
  import Text.Language.Udhr

  def build_vocabulary do
    vocabulary =
      udhr_corpus()
      |> Task.async_stream(Text.Vocabulary.Quadgram, :calculate_ngrams, [2..4], async_options())
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

end