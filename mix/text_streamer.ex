defmodule Text.Streamer do
  def stream_udhr(language, size) do
    content =
      Text.Language.Udhr.udhr_corpus()
      |> Map.fetch!(language)
      |> Text.Language.Udhr.udhr_corpus_content()

    length = String.length(content)

    Stream.resource(
      fn ->
        {content, length}
      end,
      fn {content, length} ->
        index = :rand.uniform(length - size)
        string = String.slice(content, index, size)

        {[string], {content, length}}
      end,
      fn {_content, _length} -> nil end
    )
  end

  def test(language, sample_length, options \\ []) do
    max = Keyword.get(options, :max_iterations, 1_000)
    classifier = Keyword.get(options, :classifier, Text.Language.Classifier.NaiveBayesian)
    vocabulary = Keyword.get(options, :vocabulary, Text.Vocabulary.Udhr.Multigram)

    Enum.reduce_while(stream_udhr(language, sample_length), {0, 0, 0}, fn string,
                                                                          {count, good, bad} ->
      {count, good, bad} =
        case Text.detect(string, classifier: classifier, vocabulary: vocabulary) do
          [{lang, _} | _rest] when lang == language -> {count + 1, good + 1, bad}
          _other -> {count + 1, good, bad + 1}
        end

      if count >= max do
        {:halt, {count, good, bad}}
      else
        {:cont, {count, good, bad}}
      end
    end)
  end
end
