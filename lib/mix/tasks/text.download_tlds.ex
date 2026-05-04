defmodule Mix.Tasks.Text.DownloadTlds do
  @shortdoc "Refreshes priv/extract/tlds.txt from the IANA registry"

  @moduledoc """
  Refreshes `priv/extract/tlds.txt` from
  [`data.iana.org`](https://data.iana.org/TLD/tlds-alpha-by-domain.txt).

  The TLD list is bundled in source control; this task exists to make
  refreshes reproducible and audited. The list is small (~1,440 lines,
  ~10 KB) and changes a few times per year as IANA adds or sunsets
  TLDs.

  After running, `Text.Extract.Tld` (and the regex baked into
  `Text.Extract.Scanner`) automatically picks up the new list at next
  compile.

  ## Usage

      mix text.download_tlds

  ## Options

  * `--force` — overwrite even when the on-disk file is up-to-date by
    version line. Default: only writes if the upstream is different.

  * `--diff` — print a unified diff between current and upstream
    without writing.
  """

  use Mix.Task

  @url "https://data.iana.org/TLD/tlds-alpha-by-domain.txt"
  @target Path.join(["priv", "extract", "tlds.txt"])

  @impl true
  def run(args) do
    {options, _, _} = OptionParser.parse(args, switches: [force: :boolean, diff: :boolean])

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    target_path = Path.join(File.cwd!(), @target)

    Mix.shell().info("Fetching #{@url}…")
    upstream = fetch!(@url)

    cond do
      options[:diff] ->
        print_diff(target_path, upstream)

      not File.exists?(target_path) ->
        write!(target_path, upstream)
        Mix.shell().info("Wrote #{@target} (#{lines(upstream)} lines).")

      File.read!(target_path) == upstream and not options[:force] ->
        Mix.shell().info("Already up-to-date.")

      true ->
        write!(target_path, upstream)
        Mix.shell().info("Updated #{@target} (#{lines(upstream)} lines).")
    end
  end

  defp fetch!(url) do
    headers = [{~c"user-agent", ~c"text-elixir/text.download_tlds"}]
    request = {String.to_charlist(url), headers}

    case :httpc.request(:get, request, [{:timeout, 30_000}], body_format: :binary) do
      {:ok, {{_, 200, _}, _, body}} ->
        body

      {:ok, {{_, status, reason}, _, _}} ->
        Mix.raise("HTTP #{status} #{reason} from #{url}")

      {:error, reason} ->
        Mix.raise("HTTP request failed: #{inspect(reason)}")
    end
  end

  defp write!(path, body) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
  end

  defp lines(body), do: body |> String.split("\n", trim: true) |> length()

  defp print_diff(path, upstream) do
    current = if File.exists?(path), do: File.read!(path), else: ""

    if current == upstream do
      Mix.shell().info("No changes.")
    else
      cur_lines = current |> String.split("\n", trim: true)
      up_lines = upstream |> String.split("\n", trim: true)

      added = (up_lines -- cur_lines) |> Enum.sort()
      removed = (cur_lines -- up_lines) |> Enum.sort()

      Enum.each(removed, &Mix.shell().info("- " <> &1))
      Enum.each(added, &Mix.shell().info("+ " <> &1))
    end
  end
end
