defmodule Mix.Tasks.Text.GenStopwords do
  @shortdoc "Regenerates priv/stopwords/<lang>.txt from the stopwords-iso project"

  @moduledoc """
  Fetches the [stopwords-iso](https://github.com/stopwords-iso/stopwords-iso)
  bundle (a single JSON file mapping ISO 639-1 codes to lists of stopwords)
  and writes one plain-text file per language under `priv/stopwords/`.

  The text files are checked into the repo and read by `Text.Stopwords` at
  compile time via `@external_resource`. Run this task only when the upstream
  list is updated, or when adding support for new languages.

  ## Usage

      mix text.gen_stopwords

  ## Options

  * `--source` — URL to fetch the JSON from. Defaults to the upstream
    `stopwords-iso.json` on the `master` branch of
    `stopwords-iso/stopwords-iso`.

  Source format: `{"<iso 639-1>": ["word1", "word2", ...], ...}`. License of
  the source data is MIT, which permits redistribution; see
  `priv/stopwords/LICENSE` for the upstream attribution.

  """

  use Mix.Task

  @default_source "https://raw.githubusercontent.com/stopwords-iso/stopwords-iso/master/stopwords-iso.json"

  @impl true
  def run(args) do
    {options, _, _} = OptionParser.parse(args, switches: [source: :string])
    source = Keyword.get(options, :source, @default_source)
    target_dir = Path.join([File.cwd!(), "priv", "stopwords"])
    File.mkdir_p!(target_dir)

    Mix.shell().info("Fetching #{source}")
    body = fetch!(source)
    %{} = data = :json.decode(body)

    written =
      data
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {lang, words} ->
        write_language!(target_dir, lang, words)
      end)

    Mix.shell().info("Wrote #{length(written)} language files to #{target_dir}.")
    write_license!(target_dir)
    :ok
  end

  defp fetch!(url) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    request = {String.to_charlist(url), []}

    http_options = [
      timeout: 60_000,
      connect_timeout: 30_000,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 4,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    case :httpc.request(:get, request, http_options, body_format: :binary) do
      {:ok, {{_, 200, _}, _, body}} -> body
      {:ok, {{_, status, _}, _, _}} -> Mix.raise("Fetch failed with HTTP status #{status}")
      {:error, reason} -> Mix.raise("Fetch failed: #{inspect(reason)}")
    end
  end

  defp write_language!(dir, lang, words) when is_list(words) do
    sorted = words |> Enum.uniq() |> Enum.sort()
    path = Path.join(dir, "#{lang}.txt")
    File.write!(path, Enum.map_join(sorted, "\n", & &1) <> "\n")
    {lang, length(sorted)}
  end

  defp write_license!(dir) do
    license = """
    The stopword lists in this directory are derived from the
    stopwords-iso project (https://github.com/stopwords-iso/stopwords-iso)
    and are redistributed under the same MIT license:

    MIT License

    Copyright (c) 2016 Gene Diaz

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to
    permit persons to whom the Software is furnished to do so, subject to
    the following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
    CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
    TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
    SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """

    File.write!(Path.join(dir, "LICENSE"), license)
  end
end
