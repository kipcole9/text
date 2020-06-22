defmodule Text.Language.Model.RankOrder do
  @moduledoc """
  A language detection model that uses a rank
  order coefficient to determine language
  similarity.

  """
  @no_entry %Text.Ngram.Frequency{
    rank: 1000,
    count: 0,
    frequency: 0,
    log_frequency: :math.log(5.0e-6)
  }

  def score_one_language(language, text_ngrams, vocabulary) do
    language_vocab = vocabulary.get_vocabulary(language)

    score =
      text_ngrams
      |> Enum.reduce(0, fn {ngram, %{rank: text_rank}}, score ->
        vocab_rank =
          language_vocab
          |> Map.get(ngram, @no_entry)
          |> Map.get(:rank)

        score + abs(vocab_rank - text_rank)
      end)

    {language, score}
  end

  def order_scores(scores) do
    Enum.sort(scores, fn
      {ngram1, score}, {ngram2, score} -> ngram1 < ngram2
      {_ngram1, score1}, {_ngram2, score2} -> score1 < score2
    end)
  end
end
