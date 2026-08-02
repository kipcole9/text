# Configure Nx for the test run. Without this, fastText inference and
# Bumblebee model traces both run on `Nx.BinaryBackend` (pure-Erlang)
# which is orders of magnitude slower than EXLA. Setting both the
# backend and the `defn` compiler matches the recommended production
# configuration.
#
# When `:exla` is not loaded (it is an optional dependency), this is a
# no-op and tests run on the default `Nx.BinaryBackend`.
if Code.ensure_loaded?(EXLA) do
  Nx.global_default_backend(EXLA.Backend)
  Nx.Defn.global_default_options(compiler: EXLA)
end

# Exclusion tags whose presence depends on optional deps. We skip the
# tagged tests when the dep isn't loaded; the corresponding modules are
# tagged with `@moduletag` matching these atoms.
optional_dep_excludes =
  [{Text.Stemmer, :requires_text_stemmer}]
  |> Enum.flat_map(fn {mod, tag} -> if Code.ensure_loaded?(mod), do: [], else: [tag] end)

ExUnit.start(exclude: [:requires_lid_176, :requires_bumblebee_model] ++ optional_dep_excludes)

# The fastText language identification model is 126 MB and is not committed, so the tests that need
# it are excluded by default. When a run asks for them with `--include requires_lid_176`, fetch it
# rather than failing: without the file every one of those tests errors, and confusingly — the
# `setup_all` that loads the model returns a context without it, so tests matching `%{model: model}`
# raise `FunctionClauseError` rather than reporting a missing prerequisite.
lid_176_path = Path.expand("../priv/lid_176/lid.176.bin", __DIR__)

if :requires_lid_176 in ExUnit.configuration()[:include] and not File.exists?(lid_176_path) do
  Mix.shell().info([
    :yellow,
    "lid.176.bin is required by --include requires_lid_176 and is not present. ",
    "Downloading it now (~126 MB); this happens once.",
    :reset
  ])

  Mix.Task.run("text.download_lid176")
end

# The Bumblebee sentiment model is 1.1 GB and downloads on first use. Left to itself that download
# happens *inside* a test, where ExUnit's 60 second timeout kills it part-way and leaves a truncated
# file in the Bumblebee cache — which the next test then reads as a corrupt zip
# (`Unzip.Error: Invalid local zip header`). Warming the cache here runs the download outside any
# test timeout, and populates the serving cache so the tests themselves are fast.
if :requires_bumblebee_model in ExUnit.configuration()[:include] and
     Code.ensure_loaded?(Bumblebee) do
  Mix.shell().info([
    :yellow,
    "Warming the Bumblebee sentiment model (~1.1 GB on first run); this happens once.",
    :reset
  ])

  Text.Sentiment.Backends.Bumblebee.analyze("warm up")
end
