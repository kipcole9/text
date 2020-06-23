runner =
  Text.Vocabulary.known_vocabularies
  |> Enum.map(fn vocabulary ->
    {inspect(vocabulary), &vocabulary.calculate_ngrams(hd(&1))}
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
