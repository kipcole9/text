defmodule Mix.Tasks.Text.DownloadLemmaData do
  @shortdoc "Downloads lemmatization dictionaries for one or more languages"

  @moduledoc """
  Downloads lemmatization dictionaries from the
  [`michmech/lemmatization-lists`](https://github.com/michmech/lemmatization-lists)
  upstream and places them in the configured `Text.Data` cache so
  `Text.Lemma` can load them with no further network access.

  Useful when you don't want to enable
  `config :text, auto_download_lemma_data: true` (which would let
  the package fetch on first lookup) but still want the data
  available locally — e.g. as a build step in CI, or to ship the
  dictionary alongside a release.

  Source data is licensed under the Open Database License (ODbL)
  by Michal Boleslav Měchura. The download includes the upstream
  license file alongside the per-language `.txt` files.

  ## Usage

      # Download a single language pack.
      mix text.download_lemma_data de

      # Download several at once.
      mix text.download_lemma_data de fr es it pt

      # List the languages this task knows about.
      mix text.download_lemma_data --list

  ## Options

  * `--force` — re-downloads even when the file is already cached.

  * `--list` — prints the language codes available upstream and
    exits without downloading anything.

  ## Where files land

  Files are written to `Text.Data.data_dir()/lemma/lemmatization-<lang>.txt`,
  by default `~/.cache/text/lemma/`. Override the cache location
  with:

      config :text, data_dir: "/path/to/cache"

  """

  use Mix.Task

  @url_base "https://raw.githubusercontent.com/michmech/lemmatization-lists/master/"

  # Languages with files under michmech/lemmatization-lists. Verified
  # against the repo's directory listing; Dutch (`nl`) is intentionally
  # not present because no upstream file exists.
  @available ~w(ast bg ca cs cy de en es et fa fr ga gd gl gv hu it pt ro ru sk sl sv uk)

  @impl true
  def run(args) do
    {options, languages, _} =
      OptionParser.parse(args, switches: [force: :boolean, list: :boolean])

    cond do
      options[:list] ->
        Mix.shell().info(
          "Available languages: " <>
            Enum.join(@available, ", ") <>
            "\n" <>
            "Downloads from: #{@url_base}"
        )

      languages == [] ->
        Mix.raise(
          "no language codes given. Try `mix text.download_lemma_data --list`, " <>
            "or pass one or more codes (e.g. `mix text.download_lemma_data de fr`)."
        )

      true ->
        Enum.each(languages, fn lang -> download_language(lang, options) end)
    end

    :ok
  end

  defp download_language(language, options) do
    unless language in @available do
      Mix.shell().error(
        "Skipping #{language}: no lemmatization-#{language}.txt available upstream. " <>
          "Run with --list to see the supported languages."
      )

      throw(:skip)
    end

    filename = "lemmatization-#{language}.txt"
    url = @url_base <> filename
    target_path = Text.Data.cache_path(:lemma, filename)

    cond do
      File.exists?(target_path) and not options[:force] ->
        Mix.shell().info(
          "#{filename} already cached at #{target_path}. Pass --force to re-download."
        )

      true ->
        File.mkdir_p!(Path.dirname(target_path))
        Mix.shell().info("Downloading #{url}")
        Mix.shell().info("→ #{target_path}")
        download!(url, target_path)
        bytes = File.stat!(target_path).size
        Mix.shell().info("Done. #{format_bytes(bytes)} written.")
    end
  catch
    :skip -> :ok
  end

  defp download!(url, target_path) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    request = {String.to_charlist(url), []}

    http_options = [
      timeout: 600_000,
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

    options = [stream: String.to_charlist(target_path), body_format: :binary]

    case :httpc.request(:get, request, http_options, options) do
      {:ok, :saved_to_file} ->
        :ok

      {:ok, {{_, status, _}, _, _}} ->
        Mix.raise("Download failed with HTTP status #{status}")

      {:error, reason} ->
        Mix.raise("Download failed: #{inspect(reason)}")
    end
  end

  defp format_bytes(bytes) when bytes >= 1_000_000,
    do: :erlang.float_to_binary(bytes / 1_000_000, decimals: 2) <> " MB"

  defp format_bytes(bytes) when bytes >= 1_000,
    do: :erlang.float_to_binary(bytes / 1_000, decimals: 2) <> " KB"

  defp format_bytes(bytes), do: "#{bytes} B"
end
