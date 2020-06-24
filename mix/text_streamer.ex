defmodule Text.Streamer do
  @moduledoc """
  Functions to support streaming text samples
  in various languages and to execute detection
  test cases against them.

  """

  @doc """
  Returns an Enumerable stream
  of random strings from a given language
  corpus.

  ## Arguments

  * `language` is a BCP-47 language tag in the set
    of `Text.Language.known_languages/0`

  * `sample_length` is a the length of the string
    in graphemes to be sampled and tested. For each
    iteration a new string is randomly selected
    from the language corpus.

  ## Returns

  * A random string from the corpus with a length
    of `sample_length`

  """
  def stream_udhr(language, sample_length) do
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
        index = Enum.random(1..(length - sample_length))
        string = String.slice(content, index, sample_length)

        {[string], {content, length}}
      end,
      fn {_content, _length} -> nil end
    )
  end

  @doc """
  For a given BCP-47 language, a sample length
  and options, test language detection over
  a number of iterations.

  ## Arguments

  * `language` is a BCP47 language tag in the set
    of `Text.Language.known_languages/0`

  * `sample_length` is a the length of the string
    in graphemes to be sampled and tested. For each
    iteration a new string is randomly selected
    from the language corpus.

  * `options` is a keyword list of options

  ## Options

  * `:max_iterations` is the number of iterations
    to be exectuted for each sample. The default is `1_000`

  *  `:classifier` is the classifier to be used from
    the set `Text.Language.known_classifiers/0`. The
    defautls is `Text.Language.Classifier.NaiveBayesian`

  * `:vocabulary` is the vocabulary to be used
    from the set of `Text.Vocabulary.known_vocabularies/0`.
    The default is `Text.Vocabulary.Udhr.Multigram`.

    ## Returns

  * A `{iterations, successful_detection, unsuccessful_detection}`
    tuple

  """
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

  @doc """
  Executes a language detection test
  matrix over all known classifiers
  and vocabularies for a given list
  of langauges and sample lengths.

  ## Arguments

  * `languages` is a list of BCP-47 language tag in the set
    of `Text.Language.known_languages/0`

  * `sample_length` is a list of the length of strings
    in graphemes to be sampled and tested.

  ## Returns

  * A list of lists where the inner list contains
   the test results for one matrix element. The
   elements are `[language, classifier, vocabulary,
   sample_length, iterations, correct_count,
   incorrect_count]`

  """
  def matrix(languages, lengths) when is_list(languages) and is_list(lengths) do
    for classifier <- Text.Language.known_classifiers,
        vocabulary <- Text.Vocabulary.known_vocabularies,
        language <- languages,
        sample_length <- lengths do

      {iterations, correct, incorrect} =
        test(language, sample_length, classifier: classifier, vocabulary: vocabulary)

      [language, classifier, vocabulary, sample_length, iterations, correct, incorrect]
      |> Enum.join(",")
    end
  end

  @csv_path "corpus/detection_analysis.csv"

  @headers [
    "Language", "Classifier", "Vocabulary", "Sample Length",
    "Iterations", "Correct", "Incorrect"
    ] |> Enum.join(",")

  @doc """
  Saves the results of `matrix/2` as a
  CSV file #{inspect @csv_path}.

  """
  def save_as_csv(rows) do
    rows = [@headers | rows]
    content = Enum.join(rows, "\n")
    File.write!(@csv_path, content)
  end
end
