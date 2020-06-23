language =
  "en"

text =
  Text.Streamer.stream_udhr(language, 1000)
  |> Enum.take(1)
  |> hd

concurrency_range = 1..8

runner =
  Enum.map(concurrency_range, fn n ->
    {"Concurrency #{n}", fn -> Text.Language.detect(text, max_concurrency: n) end}
  end)

Benchee.run(runner)