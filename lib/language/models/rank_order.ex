defmodule Text.Language.Model.RankOrder do
  @no_entry [100_000, :math.log(5.0e-6)]

  def order_for_ranking(results) do
    Enum.sort(results, fn
      {ngram1, score}, {ngram2, score} -> ngram1 > ngram2
      {_ngram1, score1}, {_ngram2, score2} -> score1 > score2
    end)
  end

  def score_one_language(language, text_ngrams, vocabulary) do
    language_vocab = vocabulary.get_vocabulary(language)

    score =
      text_ngrams
      |> Enum.reduce(0, fn {ngram, [text_rank, _probability]}, score ->
        [vocab_rank, _probability] = Map.get(language_vocab, ngram) || @no_entry
        score + abs(vocab_rank - text_rank)
      end)

    {language, score}
  end

  def order_scores(scores) do
    scores
    |> Enum.sort(fn {_, score1}, {_, score2} -> score1 >= score2 end)
  end
end