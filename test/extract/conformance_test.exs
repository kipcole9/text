defmodule Text.Extract.ConformanceTest do
  @moduledoc """
  Runs the [twitter-text](https://github.com/twitter/twitter-text)
  conformance fixtures against `Text.Extract.urls/2`.

  Twitter publishes a YAML test suite (`conformance/extract.yml`) used
  by every `twitter-text` port to prove behavioural parity. We vendor
  the URL-related sections under `test/fixtures/extract/` and exercise
  them here.
  """

  use ExUnit.Case, async: true

  @fixtures [
    {"twitter_urls.yml", "urls"},
    {"twitter_urls_with_indices.yml", "urls_with_indices"},
    {"twitter_urls_with_directional.yml", "urls_with_directional_markers"}
  ]

  for {file, section} <- @fixtures do
    describe "twitter-text conformance — #{section}" do
      @file_path Path.join([__DIR__, "..", "fixtures", "extract", file])

      cases =
        @file_path
        |> YamlElixir.read_from_file!()
        |> Map.fetch!(section)

      for {test_case, idx} <- Enum.with_index(cases) do
        @tag :conformance
        @tag section: section
        @tag fixture_index: idx
        test "[#{idx}] #{test_case["description"]}" do
          text = unquote(Macro.escape(test_case["text"]))
          expected = unquote(Macro.escape(test_case["expected"]))

          extracted =
            text
            |> Text.Extract.urls(twitter_quirks: true)
            |> Enum.map(& &1.url)

          assert extracted == normalise_expected(expected),
                 """
                 input:    #{inspect(text)}
                 expected: #{inspect(normalise_expected(expected))}
                 got:      #{inspect(extracted)}
                 """
        end
      end
    end
  end

  # The `urls_with_indices` fixtures use `expected: [{"url" => "...", "indices" => [s, e]}, …]`
  # We only care about the URL strings for now (span verification is a
  # separate hand-rolled test).
  defp normalise_expected(list) when is_list(list) do
    Enum.map(list, fn
      url when is_binary(url) -> url
      %{"url" => url} -> url
      other -> other
    end)
  end
end
