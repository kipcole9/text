defmodule Text.Language.Classifier.NaiveBayesian do
  @moduledoc """
  A language detection model that uses n-gram
  frequencies.

  It multiplies the frequencies of detected
  n-grams. Since the frequencies are stored
  as `log(frequency)` the addition of the
  `log(frequency)` entries is the same as
  `frequency * frequency`.

  """
  @no_entry %Text.Ngram.Frequency{
    rank: 1000,
    count: 0,
    frequency: 0,
    global_rank: 1000,
    global_frequency: 0,
    log_frequency: :math.log(5.0e-6)
  }

  @doc """
  Sums the frequencies of each n-gram

  A strong negative weighting is
  applied if the n-gram is not contained
  in the given vocabulary.
  """
  def score_one_language(language, text_ngrams, vocabulary) do
    vocab =
      vocabulary.get_vocabulary(language)

    score =
      text_ngrams
      |> Enum.reduce(0, fn {ngram, %{count: count}}, acc ->
        ngram_stats = Map.get(vocab, ngram, @no_entry)
        acc + (count * ngram_stats.log_frequency)
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
