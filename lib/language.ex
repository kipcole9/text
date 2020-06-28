defmodule Text.Language do
  @moduledoc """
  A module to support natural language
  detection.

  The primary models are implementations
  derived from [Language Identification from Text
  Using N-gram Based Cumulative Frequency Addition](http://www.csis.pace.edu/~ctappert/srd2004/paper12.pdf)

  """

  @known_classifiers [
    Text.Language.Classifier.NaiveBayesian,
    Text.Language.Classifier.CummulativeFrequency,
    Text.Language.Classifier.RankOrder
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

  * `:corpus` is a module encapsulating a body of
    text in one or more natural languages.A corpus
    module implements the `Text.Corpus` behaviour.
    The default is `Text.Corpus.Udhr` which is implemented by the
    [text_corpus_udhr](https://hex.pm/packages/text_corpus_udhr)
    package. This package must be installed as a dependency in
    order for this default to be used.

  * `:classifier` is the module used to detect the language.
    The default is `Text.Language.Classifier.NaiveBayesian`.
    Other classifiers are `Text.Language.Classifier.RankOrder`,
    `Text.Classifier.CummulativeFrequency` and
    `Text.Language.Classifier.Spearman`. Any module that
    implements the `Text.Language.Classifier` behaviour
    may be used.

  * `:vocabulary` is the vocabulary to be used. The
    default is `hd(corpus.known_vocabularies())`. Available
    vocabularies are returned from `corpus.known_vocabularies/0`.

  * `:only` is a list of languages to be used
    as candidates for the language of `text`. The
    default is `corpus.known_languages/0`
    which is all the lanuages known to a given
    corpus.

  * `:max_demand` is used to determine the batch size
    for `Flow.from_enumerable/1`. The default is
    `#{@default_max_demand}`.

  ## Returns

  * A list of `2-tuples` in order of confidence with
    the first element being the BCP-47 language code
    and the second element being the score as determined
    by the requested classifier. The score has no meaning
    except to order the results by confidence level.

  ## Examples

  """
  @spec detect(String.t, Keyword.t) :: Text.Language.Classifier.frequency_list()

  def detect(text, options \\ []) when is_binary(text) do
    corpus = Keyword.get(options, :corpus, Text.Corpus.Udhr)
    classifier = Keyword.get(options, :classifier, Text.Language.Classifier.NaiveBayesian)
    vocabulary = Keyword.get(options, :vocabulary)
    languages = Keyword.get(options, :only, corpus.known_languages())
    max_demand = Keyword.get(options, :max_demand, @default_max_demand)

    with {:ok, corpus} <- validate(:corpus, corpus),
         {:ok, classifier} <- validate(:classifier, classifier),
         {:ok, vocabulary} <- validate(:vocabulary, corpus, vocabulary),
         {:ok, languages} <- validate(:only, corpus, languages) do
      ensure_vocabulary_loaded!(vocabulary)

      text_ngrams =
        text
        |> corpus.normalize_text
        |> vocabulary.calculate_ngrams

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
  @spec known_classifiers :: [Text.Language.Classifier.t, ...]
  def known_classifiers do
    @known_classifiers
  end

  @doc """
  Function to remove text elements that
  interfer with language detection.

  Each corpus has a callback `normalize_text/1`
  that is applied when training the
  classifier and when detecting language
  from natural text. If desired, the corpus
  can delegate to this function.

  ## Argument

  * `text` is any `String.t`

  ## Returns

  * A normalized `String.t`

  """
  @spec normalize_text(String.t) :: String.t
  def normalize_text(text) do
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

  defp ensure_vocabulary_loaded!(vocabulary) do
    :persistent_term.get({vocabulary, :languages}, nil) || vocabulary.load_vocabulary!
  end

  defp validate(:corpus, corpus) when is_atom(corpus) do
    if corpus_module?(corpus) do
      {:ok, corpus}
    else
      {:error, {ArgumentError, "Unknown corpus #{inspect(corpus)}"}}
    end
  end

  defp validate(:classifier, classifier) when classifier in @known_classifiers do
    {:ok, classifier}
  end

  defp validate(:classifier, classifier) do
    {:error,
     {ArgumentError,
      "Unknown classifier #{inspect(classifier)}. " <>
        "Known classifiers are #{inspect(@known_classifiers)}."}}
  end

  defp validate(:vocabulary, corpus, nil) do
    known_vocabularies = corpus.known_vocabularies
    validate(:vocabulary, corpus, hd(known_vocabularies))
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

  @doc false
  def corpus_module?(corpus) do
    Code.ensure_loaded?(corpus) && function_exported?(corpus, :known_vocabularies, 0)
  end
end
