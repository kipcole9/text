defmodule Mix.Tasks.Text.GenGoldenFixtures do
  @shortdoc "Generates golden lid.176 prediction fixtures for differential testing"

  @moduledoc """
  Runs the canonical test inputs through the reference fastText
  implementation and writes per-input top-K predictions to
  `test/fixtures/golden_predictions.json`.

  Acts as a thin wrapper over `priv/scripts/generate_golden_fixtures.py` so
  the workflow is consistent with `mix text.download_lid176`. The wrapper
  simply ensures the prerequisites exist and shells out to Python; it does
  not embed any model logic itself.

  ## Prerequisites

  * Python 3.8 or newer.

  * The `fasttext` Python package: `pip install fasttext`.

  * The `lid.176.bin` model file present in `priv/lid_176/` — run
    `mix text.download_lid176` first.

  ## Usage

      mix text.gen_golden_fixtures
      mix text.gen_golden_fixtures --top-k 10

  ## Options

  * `--top-k N` — number of predictions to record per input (default 5).

  * `--python PATH` — path to the Python interpreter (default: `python3`).

  Any unrecognised options are forwarded to the underlying script
  unchanged.

  """

  use Mix.Task

  @impl true
  def run(args) do
    {options, rest, _} =
      OptionParser.parse(args,
        strict: [python: :string, top_k: :integer],
        aliases: [k: :top_k]
      )

    python = options[:python] || "python3"

    script_path =
      Path.join([File.cwd!(), "priv", "scripts", "generate_golden_fixtures.py"])

    if not File.exists?(script_path) do
      Mix.raise("Generator script not found at #{script_path}")
    end

    model_path = Path.join([File.cwd!(), "priv", "lid_176", "lid.176.bin"])

    if not File.exists?(model_path) do
      Mix.raise(
        "lid.176.bin not found at #{model_path}. " <>
          "Run `mix text.download_lid176` first."
      )
    end

    forwarded = build_args(options, rest)

    Mix.shell().info("$ #{python} #{script_path} #{Enum.join(forwarded, " ")}")

    case System.cmd(python, [script_path | forwarded],
           cd: File.cwd!(),
           stderr_to_stdout: true,
           into: IO.stream(:stdio, :line)
         ) do
      {_, 0} ->
        :ok

      {_, status} ->
        Mix.raise("Generator script exited with status #{status}")
    end
  end

  defp build_args(options, rest) do
    forwarded =
      Enum.flat_map(options, fn
        {:python, _} -> []
        {:top_k, n} -> ["--top-k", Integer.to_string(n)]
      end)

    forwarded ++ rest
  end
end
