defmodule Text.Language.Classifier do
  @type frequency_list :: [Text.frequency_tuple(), ...]
  @type text_ngrams :: %{charlist => Text.Ngram.Frequency.t}

  @callback score_one_language(Text.language, text_ngrams, Text.vocabulary) :: frequency_list()
  @callback order_scores(frequency_list) :: frequency_list()

end