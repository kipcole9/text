defmodule Text.Language.Classifier do
  @moduledoc """
  A behaviour definition module for language
  classifiers.

  A language classifier correlates supplied
  natural language text against a vocabulary
  and returns a score indicating how closely the
  supplied text matches the vocabulary.

  """

  @typedoc "A classifier is a module that implements the `Text.Language.Classifier` behaviour."
  @type t :: module()

  @typedoc "A list of 2-tuples of the form `{language, number}`"
  @type frequency_list :: [Text.frequency_tuple(), ...]

  @typedoc "A list mapping an n-gram as a charlist to a `Text.Ngram.Frequency struct`"
  @type text_ngrams :: %{charlist => Text.Ngram.Frequency.t}

  @doc """
  Returns the classifier score for one language.

  A classifier correlates how closely a
  supplied string (encoded into n-grams)
  matches against a given language profile
  implemented as a vocabulary.

  See `Text.Language.Classifier.NaiveBayesian`
  for an example.

  """
  @callback score_one_language(Text.language, text_ngrams, Text.vocabulary) :: frequency_list()

  @doc """
  Sorts the classifier scores from all languages in
  order or correlation.
  """
  @callback order_scores(frequency_list) :: frequency_list()

end