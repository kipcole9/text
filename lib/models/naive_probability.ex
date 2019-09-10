defmodule Text.Language.Model.NaiveProbability do
  @no_entry [1000, :math.log(5.0e-6)]

  def score_one_language(language, text_ngrams, vocabulary) do
    score =
      text_ngrams
      |> Enum.reduce(0, fn {ngram, [_index, _probability]}, acc ->
        language = vocabulary.get_vocabulary(language)
        [_index, probability] = Map.get(language, ngram) || @no_entry
        acc + probability
      end)

    {language, score}
  end
end