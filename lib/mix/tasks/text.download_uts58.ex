defmodule Mix.Tasks.Text.DownloadUts58 do
  @shortdoc "Refreshes the vendored UTS #58 conformance test files"

  # The release the vendored fixtures were taken from. Bump when they are regenerated. Declared
  # before `@moduledoc` so the documentation can name the current default.
  @default_release "draft"

  @moduledoc """
  Refreshes the [UTS #58](https://www.unicode.org/reports/tr58/) conformance test files vendored
  under `test/fixtures/uts58/`.

  The files are bundled in source control so the test suite runs offline and a conformance change
  shows up as a reviewable diff rather than a silent behaviour shift. This task makes refreshing
  them reproducible.

  Like the Unicode data files, these are published per release, with a pre-release tree that carries
  no version segment in its path at all:

      https://www.unicode.org/Public/<release>/linkification/
      https://www.unicode.org/Public/draft/linkification/

  A *release channel* is therefore either a version string such as `"17.0.0"` or the literal
  `"draft"`, and the URL is built by a function rather than by interpolating a version into a
  template.

  ## Usage

      mix text.download_uts58
      mix text.download_uts58 --release draft
      mix text.download_uts58 --diff
      mix text.download_uts58 --into tmp/uts58
      mix text.download_uts58 --dry-run

  ## Options

  * `--release` — the release channel to fetch from. The default is the first of the
    `UNICODE_RELEASE` environment variable, the `:release` key of the `:unicode` application
    environment, or `#{@default_release}`. The environment variable is shared with the `unicode`
    library's own download task so a single setting retargets both.

  * `--into` — the directory to download into. The default is `test/fixtures/uts58`. Downloading to
    a scratch directory allows a candidate release to be diffed before adopting it.

  * `--diff` — report which lines would be added and removed without writing anything.

  * `--dry-run` — print the resolved URL and destination of each file without downloading.

  * `--force` — write even when the local file is already identical. Without it, unchanged files
    are left alone and reported as up-to-date.

  """

  use Mix.Task

  @draft_release "draft"

  @target_dir Path.join(["test", "fixtures", "uts58"])

  @files ["LinkDetectionTest.txt", "LinkFormattingTest.txt"]

  @switches [release: :string, into: :string, diff: :boolean, dry_run: :boolean, force: :boolean]

  @impl true
  def run(argv) do
    {options, _argv, _invalid} = OptionParser.parse(argv, switches: @switches)

    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    release = release(options)
    directory = options[:into] || @target_dir

    Enum.each(@files, &handle_file(&1, release, directory, options))
  end

  defp handle_file(file, release, directory, options) do
    url = Path.join(linkification_root(release), file)
    target = Path.join(directory, file)

    if options[:dry_run] do
      Mix.shell().info("#{url} -> #{target}")
    else
      Mix.shell().info("Fetching #{url}…")
      write_or_report(target, fetch!(url), options)
    end
  end

  defp write_or_report(target, upstream, options) do
    cond do
      options[:diff] ->
        print_diff(target, upstream)

      not File.exists?(target) ->
        write!(target, upstream)
        Mix.shell().info("Wrote #{target} (#{cases(upstream)} cases).")

      File.read!(target) == upstream and !options[:force] ->
        Mix.shell().info("#{target} already up-to-date.")

      true ->
        write!(target, upstream)
        Mix.shell().info("Updated #{target} (#{cases(upstream)} cases).")
    end
  end

  # The pre-release tree has no version segment, so this cannot be a single interpolated template.
  defp linkification_root(@draft_release),
    do: "https://www.unicode.org/Public/draft/linkification/"

  defp linkification_root(release),
    do: "https://www.unicode.org/Public/#{release}/linkification/"

  defp release(options) do
    options[:release] || System.get_env("UNICODE_RELEASE") ||
      Application.get_env(:unicode, :release) || @default_release
  end

  defp fetch!(url) do
    headers = [{~c"user-agent", ~c"text-elixir/text.download_uts58"}]
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

  # Both files ignore blank lines and lines beginning with `#`, so this counts what the suite will
  # actually run rather than raw lines.
  defp cases(body) do
    body
    |> String.split("\n")
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> length()
  end

  defp print_diff(path, upstream) do
    current = if File.exists?(path), do: File.read!(path), else: ""

    if current == upstream do
      Mix.shell().info("No changes to #{path}.")
    else
      current_lines = String.split(current, "\n", trim: true)
      upstream_lines = String.split(upstream, "\n", trim: true)

      Enum.each(current_lines -- upstream_lines, &Mix.shell().info("- " <> &1))
      Enum.each(upstream_lines -- current_lines, &Mix.shell().info("+ " <> &1))
    end
  end
end
