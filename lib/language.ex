defmodule Text.Language do

  def detect(text,
      model \\ Text.Language.Model.NaiveProbability,
      vocabulary \\ Text.Vocabulary.Quadgram,
      target_languages \\  Text.Language.Udhr.known_languages()) do
    text_ngrams = vocabulary.calculate_ngrams(text)

    target_languages
    |> Task.async_stream(model, :score_one_language, [text_ngrams, vocabulary], async_options())
    |> Enum.map(&elem(&1, 1))
    |> model.order_scores
  end

  @doc false
  def async_options do
    [max_concurrency: System.schedulers_online() * 8, timeout: :infinity, ordered: false]
  end

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

end