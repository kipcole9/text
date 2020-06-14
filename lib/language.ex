defmodule Text.Language do
  @moduledoc """
  A module to support natural language
  detection.

  The primary models are implemnetations
  derived from [Language Identification from Text
  Using N-gram Based Cumulative Frequency Addition](http://www.csis.pace.edu/~ctappert/srd2004/paper12.pdf)

  """

  @known_models [
    Text.Language.Model.NaiveProbability,
    Text.Language.Model.RankOrder,
    Text.Language.Model.Spearman
  ]

  @known_vocabularies Text.Vocabulary.known_vocabularies()

  @known_languages Text.Language.Udhr.known_languages()

  @doc """
  Detect the language of a given text.

  ## Arguments

  * `text` is a binary text from which
    the language is detected

  * `options` is a keyword list of
    options.

  ## Options

  * `:model` is the module used to detect the language.
    The default is `Text.Language.Model.NaiveProbability`.
    Other models are `Text.Language.Model.RankOrder` and
    `Text.Language.Model.Spearman`

  * `:vocabulary` is the vocabulary to be used. The
    default is `Text.Vocabulary.Multigram`. Other
    vocabularies are `Text.Vocabulary.Quadgram` and
    `Text.Vocabulary.Bigram`.

  * `:only` is a list of languages to be used
    as candidates for the language of `text`. The
    default is `Text.Language.Udhr.known_languages/0`
    which is all the lanuages known to `Text.Language`.

  ## Returns

  * A list of `2-tuples` in order of confidence with
    the first element being the BCP47 language code
    and the second element being the score as determined
    by the requested model.

  ## Examples

  """
  def detect(text, options \\ []) when is_binary(text) do
    model = Keyword.get(options, :model, Text.Language.Model.NaiveProbability)
    vocabulary = Keyword.get(options, :vocabulary, Text.Vocabulary.Multigram)
    languages = Keyword.get(options, :only, Text.Language.Udhr.known_languages())

    with {:ok, _} <- validate(:model, model),
         {:ok, _} <- validate(:vocabulary, vocabulary),
         {:ok, _} <- validate(:only, languages) do

      ensure_vocabulary_loaded!(vocabulary)
      text_ngrams = vocabulary.calculate_ngrams(text)

      languages
      |> Task.async_stream(model, :score_one_language, [text_ngrams, vocabulary], async_options())
      |> Enum.map(&elem(&1, 1))
      |> model.order_scores
    end
  end

  @doc false
  def async_options do
    [max_concurrency: System.schedulers_online() * 8, timeout: :infinity, ordered: false]
  end

  @doc """
  Function to remove text elements that
  interfer with language detection.

  """
  def normalise_text(text) do
    text
    # Downcase
    |> String.downcase
		# Make sure that there is letter before punctuation
		|> String.replace(~r/\.\s*/u, "_")
		# Discard all digits
		|> String.replace(~r/[0-9]/u, "")
		# Discard all punctuation except for apostrophe
		|> String.replace(~r/[&\/\\#,+()$~%.":*?<>{}]/u,"")
		# Remove duplicate spaces
		|> String.replace(~r/\s+/u, " ")
  end

  defp ensure_vocabulary_loaded!(vocabulary) do
    :persistent_term.get({vocabulary, :languages}, nil) || vocabulary.load_vocabulary!
  end

  defp validate(:model, model) when model in @known_models do
    {:ok, model}
  end

  defp validate(:model, model) do
    {:error,
      {ArgumentError,
        "Unknown model #{inspect model}. " <>
        "Known models are #{inspect @known_models}."
    }}
  end

  defp validate(:vocabulary, vocabulary) when vocabulary in @known_vocabularies do
    {:ok, vocabulary}
  end

  defp validate(:vocabulary, vocabulary) do
    {:error,
      {ArgumentError,
        "Unknown vocabulary #{inspect vocabulary}. " <>
        "Known vocabularies are #{inspect @known_vocabularies}."
    }}
  end

  defp validate(:only, languages) do
    unknown_languages = Enum.filter(languages, &(&1 not in @known_languages))
    if unknown_languages == [] do
      {:ok, languages}
    else
      {:error,
        {ArgumentError,
          "Unknown languages #{inspect unknown_languages}. " <>
          "Known languages are #{inspect @known_languages}."
      }}
    end
  end

end