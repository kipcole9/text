defmodule Mix.Tasks.Text.DownloadModel do
  @shortdoc "Downloads the fastText lid.176.bin language identification model"

  @moduledoc """
  Downloads the fastText `lid.176.bin` model file used by
  `Text.Language.Classifier.Fasttext` for language identification.

  The model is fetched from `dl.fbaipublicfiles.com` (the official fastText
  distribution endpoint) and saved to `priv/lid_176/lid.176.bin` inside this
  project.

  The binary is approximately 126 MB and is **not** committed to the repo.
  Run this task once after cloning, or whenever you need to refresh the
  model.

  ## Usage

      mix text.download_model

  ## Options

  * `--force` — re-downloads even if `lid.176.bin` is already present.

  * `--quantized` — downloads `lid.176.ftz` (the 917 KB quantized variant)
    instead of the full model. Currently informational only:
    `Text.Language.Classifier.Fasttext` does not yet support the quantized
    format.

  """

  use Mix.Task

  @full_url "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin"
  @quantized_url "https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.ftz"

  @impl true
  def run(args) do
    {options, _, _} =
      OptionParser.parse(args, switches: [force: :boolean, quantized: :boolean])

    {url, filename} =
      if options[:quantized] do
        {@quantized_url, "lid.176.ftz"}
      else
        {@full_url, "lid.176.bin"}
      end

    target_dir = Path.join([File.cwd!(), "priv", "lid_176"])
    target_path = Path.join(target_dir, filename)

    cond do
      File.exists?(target_path) and not options[:force] ->
        Mix.shell().info(
          "#{filename} already present at #{target_path}. Pass --force to re-download."
        )

      true ->
        File.mkdir_p!(target_dir)
        Mix.shell().info("Downloading #{url}")
        Mix.shell().info("→ #{target_path}")
        download!(url, target_path)
        bytes = File.stat!(target_path).size
        Mix.shell().info("Done. #{format_bytes(bytes)} written.")
    end

    :ok
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

  defp format_bytes(bytes) when bytes >= 1_000_000_000,
    do: :erlang.float_to_binary(bytes / 1_000_000_000, decimals: 2) <> " GB"

  defp format_bytes(bytes) when bytes >= 1_000_000,
    do: :erlang.float_to_binary(bytes / 1_000_000, decimals: 2) <> " MB"

  defp format_bytes(bytes) when bytes >= 1_000,
    do: :erlang.float_to_binary(bytes / 1_000, decimals: 2) <> " KB"

  defp format_bytes(bytes), do: "#{bytes} B"
end
