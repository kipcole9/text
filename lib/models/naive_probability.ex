defmodule Text.Language.Model.NaiveProbability do
  alias Text.Ngram
  import Text.Language, only: [async_options: 0]

  @ngram 4
  @no_entry [1000, :math.log(5.0e-6)]

  def detect(text, vocabulary) do
    text_ngrams = Ngram.ngram(text, @ngram)

    Text.Language.Udhr.known_languages()
    |> Task.async_stream(__MODULE__, :detect_one_language, [text_ngrams, vocabulary], async_options())
    |> Enum.map(&elem(&1, 1))
    |> Enum.sort_by(fn {_, score} -> score end)
    |> Enum.reverse
  end

  def detect_one_language(language, text_ngrams, vocabulary) do
    score =
      text_ngrams
      |> Enum.reduce(0, fn {ngram, _count}, acc ->
        language = vocabulary.get_vocabulary(language)
        [_index, probability] = Map.get(language, ngram) || @no_entry
        acc + probability
      end)

    {language, score}
  end
end