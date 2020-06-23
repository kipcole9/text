runner =
  Text.Language.known_classifiers
  |> Enum.map(fn classifier ->
    {inspect(classifier), &Text.Language.detect(hd(&1), classifier: classifier)}
  end)

language = "en"

Benchee.run(
  runner,
  inputs: %{
    "50 characters" => Enum.take(Text.Streamer.stream_udhr(language, 50), 1),
    "100 characters" => Enum.take(Text.Streamer.stream_udhr(language, 100), 1),
    "150 characters" => Enum.take(Text.Streamer.stream_udhr(language, 150), 1),
  }
)