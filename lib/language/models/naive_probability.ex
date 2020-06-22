defmodule Text.Language.Model.NaiveProbability do
  @moduledoc """
  A language detection model that uses naive
  probabilities.

  It sums the probabilities of detected
  n-grams. Since the probabilities are stored
  as `log(probability)` the addition of the
  `log(probabiity)` entries is the same as
  `probability * probability`.

  """
  @no_entry %Text.Ngram.Frequency{
    rank: 1000,
    count: 0,
    frequency: 0,
    log_frequency: :math.log(5.0e-6)
  }

  @doc """
  Sums the frequencies of each n-gram

  A strong negative weighting is
  applied if the n-gram is not contained
  in the given vocabulary.
  """
  def score_one_language(language, text_ngrams, vocabulary) do
    score =
      text_ngrams
      |> Enum.reduce(0, fn {ngram, _}, acc ->
        language = vocabulary.get_vocabulary(language)
        ngram = Map.get(language, ngram, @no_entry)
        acc + ngram.log_frequency
      end)

    {language, score}
  end

  def order_scores(scores) do
    scores
    |> Enum.sort(fn
      {ngram1, score}, {ngram2, score} -> ngram1 > ngram2
      {_, score1}, {_, score2} -> score1 >= score2
    end)
  end
end
