defmodule Text.Language do
  @moduledoc """
  A module to support natural language
  detection.

  The primary models are implemnetations
  derived from [Language Identification from Text
  Using N-gram Based Cumulative Frequency Addition](http://www.csis.pace.edu/~ctappert/srd2004/paper12.pdf)

  """

  @known_classifiers [
    Text.Language.Classifier.NaiveBayesian,
    Text.Language.Classifier.CummulativeFrequency,
    Text.Language.Classifier.RankOrder
    # Text.Language.Classifier.Spearman
  ]

  @default_max_demand 20

  @doc """
  Identify the natural language of a given text.

  ## Arguments

  * `text` is a binary text from which
    the language is detected.

  * `options` is a keyword list of
    options.

  ## Options

  * `:classifier` is the module used to detect the language.
    The default is `Text.Language.Classifier.NaiveBayesian`.
    Other models are `Text.Language.Classifier.RankOrder`,
    `Text.Classifier.CummulativeFrequency` and
    `Text.Language.Classifier.Spearman`

  * `:vocabulary` is the vocabulary to be used. The
    default is `Text.Vocabulary.Udhr.Multigram`. Other
    vocabularies are `Text.Vocabulary.Udhr.Quadgram` and
    `Text.Vocabulary.Udhr.Bigram`.

  * `:only` is a list of languages to be used
    as candidates for the language of `text`. The
    default is `Text.Language.Udhr.known_languages/0`
    which is all the lanuages known to `Text.Language`.

  * `:max_demand` is used to determine the batch size
    for `Flow.from_enumerable/1`. The default is
    `#{@default_max_demand}`.

  ## Returns

  * A list of `2-tuples` in order of confidence with
    the first element being the BCP47 language code
    and the second element being the score as determined
    by the requested classifier. The score has no meaning
    except to order the results by confidence level.

  ## Examples

  """
  def detect(text, options \\ []) when is_binary(text) do
    corpus = Keyword.get(options, :corpus, Text.Corpus.Udhr)
    classifier = Keyword.get(options, :model, Text.Language.Classifier.NaiveBayesian)
    vocabulary = Keyword.get(options, :vocabulary, Text.Vocabulary.Udhr.Multigram)
    languages = Keyword.get(options, :only, corpus.known_languages())
    max_demand = Keyword.get(options, :max_demand, @default_max_demand)

    with {:ok, _} <- validate(:classifier, classifier),
         {:ok, _} <- validate(:vocabulary, corpus, vocabulary),
         {:ok, _} <- validate(:only, corpus, languages) do
      ensure_vocabulary_loaded!(corpus, vocabulary)
      text_ngrams = vocabulary.calculate_ngrams(text)

      languages
      |> Flow.from_enumerable(max_demand: max_demand)
      |> Flow.map(&classifier.score_one_language(&1, text_ngrams, vocabulary))
      |> Enum.to_list
      |> classifier.order_scores()
    end
  end

  @doc """
  Returns a list of the known
  classifiers that can be applied as
  a `:classifer` option to `Text.Language.detect/2`

  """
  def known_classifiers do
    @known_classifiers
  end

  @doc """
  Function to remove text elements that
  interfer with language detection.

  """
  def normalise_text(text) do
    text
    # Downcase
    |> String.downcase()
    # Make sure that there is letter before punctuation
    |> String.replace(~r/\.\s*/u, "_")
    # Discard all digits
    |> String.replace(~r/[0-9]/u, "")
    # Discard all punctuation except for apostrophe
    |> String.replace(~r/[&\/\\#,+()$~%.":*?<>{}]/u, "")
    # Remove duplicate spaces
    |> String.replace(~r/\s+/u, " ")
  end

  defp ensure_vocabulary_loaded!(corpus, vocabulary) do
    :persistent_term.get({corpus, vocabulary, :languages}, nil) || vocabulary.load_vocabulary!
  end

  defp validate(:classifier, model) when model in @known_classifiers do
    {:ok, model}
  end

  defp validate(:classifier, model) do
    {:error,
     {ArgumentError,
      "Unknown model #{inspect(model)}. " <>
        "Known models are #{inspect(@known_classifiers)}."}}
  end

  defp validate(:vocabulary, corpus, vocabulary) do
    known_vocabularies = corpus.known_vocabularies

    if vocabulary in corpus.known_vocabularies do
      {:ok, vocabulary}
    else
      {:error,
        {ArgumentError,
          "Unknown vocabulary #{inspect(vocabulary)}. " <>
          "Known vocabularies are #{inspect(known_vocabularies)}."
      }}
    end
  end

  defp validate(:only, corpus, languages) do
    known_languages = corpus.known_languages
    unknown_languages = Enum.filter(languages, &(&1 not in known_languages))

    if unknown_languages == [] do
      {:ok, languages}
    else
      {:error,
       {ArgumentError,
        "Unknown languages #{inspect(unknown_languages)}. " <>
          "Known languages are #{inspect(known_languages)}."}}
    end
  end
end
