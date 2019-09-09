defmodule Text.Language do

  def detect(text, model \\ Text.Language.Model.NaiveProbability, vocabulary \\ Text.Vocabulary.Quadgram) do
    model.detect(text, vocabulary.get_vocabulary())
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