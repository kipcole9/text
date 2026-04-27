#!/usr/bin/env elixir
# Comparative performance script for the fastText classifier port.
#
# Measures three things side-by-side against the official `fasttext`
# Python bindings on `lid.176`:
#
#   * Accuracy — top-1 label match across the curated test inputs and
#     the golden prediction fixtures.
#
#   * Speed — cold model load time + per-prediction wall time on a
#     spread of input lengths and scripts.
#
#   * Memory — model resident footprint after load + per-prediction
#     allocations.
#
# Output goes to stdout. The companion shell wrapper
# `priv/scripts/run_perf_report.sh` runs both this Elixir script and a
# matching Python script, then `docs/comparative_performance_report.md`
# stitches the numbers together.
#
# Run with:
#
#     mix run priv/scripts/comparative_perf_report.exs

alias Text.Language.Classifier.Fasttext
alias Text.Language.Classifier.Fasttext.{Features, Inference, ModelLoader, Tokenizer}

# Switch to EXLA for the matrix work AND configure it as the default
# `defn` compiler. The Inference module uses `defn` to fuse `take + mean
# + dot` (and the softmax tail) into a single graph; with EXLA as the
# compiler that whole graph runs as one native kernel call rather than
# 4–8 separate BEAM ↔ NIF round-trips.
case Code.ensure_loaded?(EXLA.Backend) do
  true ->
    Nx.global_default_backend(EXLA.Backend)
    Nx.Defn.global_default_options(compiler: EXLA)
    IO.puts("Backend: EXLA (defn compiler: EXLA)")

  false ->
    IO.puts(
      "Backend: Nx.BinaryBackend (EXLA not available — install :exla for full speed)"
    )
end

model_path = Path.join([File.cwd!(), "priv", "lid_176", "lid.176.bin"])

unless File.exists?(model_path) do
  IO.puts(:stderr, "lid.176.bin not found. Run `mix text.download_model` first.")
  System.halt(1)
end

inputs_path = Path.join([File.cwd!(), "test", "fixtures", "test_strings.json"])
inputs = inputs_path |> File.read!() |> :json.decode() |> Map.fetch!("strings")

predictions_path = Path.join([File.cwd!(), "test", "fixtures", "golden_predictions.json"])

reference_predictions =
  if File.exists?(predictions_path) do
    predictions_path |> File.read!() |> :json.decode() |> Map.fetch!("entries")
  else
    []
  end

bench_inputs = %{
  "short ASCII (3 words)" => "the cat sat",
  "medium ASCII (10 words)" =>
    "the quick brown fox jumps over the lazy dog now",
  "long sentence (~80 chars)" =>
    "Hello world. This is an English sentence used for language identification testing.",
  "Cyrillic" => "Это русское предложение для определения языка.",
  "CJK (Chinese)" => "这是一个用于语言识别的中文句子。",
  "CJK (Japanese)" => "これは言語識別のための日本語の文です。"
}

# ---- Memory baseline ---------------------------------------------------

# Force a major GC to give a clean baseline.
:erlang.garbage_collect()
mem_before_load = :erlang.memory(:total)

IO.puts("\n=== Loading model ===")
{load_us, {:ok, model}} = :timer.tc(fn -> ModelLoader.load(model_path) end)
:erlang.garbage_collect()
mem_after_load = :erlang.memory(:total)

load_ms = Float.round(load_us / 1000, 1)
load_mb = Float.round((mem_after_load - mem_before_load) / 1024 / 1024, 1)

IO.puts("Load time: #{load_ms} ms")
IO.puts("Resident model memory: #{load_mb} MB")
IO.puts("nwords=#{model.dictionary.nwords} nlabels=#{model.dictionary.nlabels}")
IO.puts("input matrix: #{inspect(Nx.shape(model.input_matrix))} #{inspect(Nx.type(model.input_matrix))}")

# ---- Accuracy: curated test set ----------------------------------------

IO.puts("\n=== Accuracy on curated test inputs ===")

curated_results =
  Enum.map(inputs, fn entry ->
    text = Map.fetch!(entry, "text")
    expected = Map.fetch!(entry, "expected_label")
    {:ok, det} = Fasttext.detect(text, model, k: 1)
    correct? = String.split(det.language, "-") |> List.first() == expected

    %{
      text: text,
      expected: expected,
      predicted: det.language,
      confidence: det.confidence,
      correct?: correct?
    }
  end)

correct = Enum.count(curated_results, & &1.correct?)
total = length(curated_results)
mean_conf =
  curated_results
  |> Enum.map(& &1.confidence)
  |> case do
    [] -> 0.0
    cs -> Enum.sum(cs) / length(cs)
  end

IO.puts("Top-1 accuracy: #{correct}/#{total} (#{Float.round(correct / total * 100, 1)}%)")
IO.puts("Mean top-1 confidence: #{Float.round(mean_conf, 3)}")

# ---- Reference parity --------------------------------------------------

if reference_predictions != [] do
  IO.puts("\n=== Reference parity (vs `fasttext` Python bindings) ===")

  parity_results =
    Enum.map(reference_predictions, fn entry ->
      text = Map.fetch!(entry, "text")
      ref_top = entry |> Map.fetch!("predictions") |> hd() |> Map.fetch!("label")
      ref_prob = entry |> Map.fetch!("predictions") |> hd() |> Map.fetch!("probability")
      {:ok, det} = Fasttext.detect(text, model, k: 1)

      %{
        text: text,
        ref_label: ref_top,
        ref_prob: ref_prob,
        our_label: det.language,
        our_prob: det.confidence,
        label_match?: det.language == ref_top,
        prob_delta: abs(det.confidence - ref_prob)
      }
    end)

  label_matches = Enum.count(parity_results, & &1.label_match?)
  total_parity = length(parity_results)
  max_delta = parity_results |> Enum.map(& &1.prob_delta) |> Enum.max()
  mean_delta = parity_results |> Enum.map(& &1.prob_delta) |> Enum.sum() |> Kernel./(total_parity)

  IO.puts(
    "Top-1 label parity: #{label_matches}/#{total_parity} (#{Float.round(label_matches / total_parity * 100, 1)}%)"
  )

  IO.puts("Top-1 probability mean Δ: #{:erlang.float_to_binary(mean_delta, decimals: 6)}")
  IO.puts("Top-1 probability max Δ:  #{:erlang.float_to_binary(max_delta, decimals: 6)}")
end

# ---- Speed -------------------------------------------------------------

IO.puts("\n=== Speed (per prediction, warm) ===")

# Skip benchee in scripts that want bare-metal numbers; manual timing is
# clearer for a comparative report than benchee's full output.
warmup_count = 50
measure_count = 200

speed_results =
  for {label, text} <- bench_inputs do
    # Warmup
    Enum.each(1..warmup_count, fn _ ->
      Inference.predict(text, model, k: 1)
    end)

    samples_us =
      for _ <- 1..measure_count do
        {us, _result} = :timer.tc(fn -> Inference.predict(text, model, k: 1) end)
        us
      end

    sorted = Enum.sort(samples_us)
    median_us = Enum.at(sorted, div(measure_count, 2))
    p99_us = Enum.at(sorted, div(measure_count * 99, 100))

    {label, median_us, p99_us}
  end

IO.puts("input                                    median (μs)   p99 (μs)")
IO.puts("---------------------------------------- ------------- ----------")

for {label, median, p99} <- speed_results do
  IO.puts(
    "#{String.pad_trailing(label, 40)} #{String.pad_leading(Integer.to_string(median), 13)} #{String.pad_leading(Integer.to_string(p99), 10)}"
  )
end

# ---- Memory: per-prediction allocation ---------------------------------

IO.puts("\n=== Memory per prediction ===")

mem_results =
  for {label, text} <- bench_inputs do
    # Warm up.
    _ = Inference.predict(text, model, k: 1)
    :erlang.garbage_collect()

    {_words, total_before} = {:erlang.memory(:processes), :erlang.memory(:total)}
    n = 100
    Enum.each(1..n, fn _ -> Inference.predict(text, model, k: 1) end)
    total_after = :erlang.memory(:total)

    mb_per_call = (total_after - total_before) / n / 1024 / 1024
    {label, mb_per_call}
  end

IO.puts("input                                    MB / prediction (allocated, pre-GC)")
IO.puts("---------------------------------------- ----------------------------------")

for {label, mb} <- mem_results do
  IO.puts("#{String.pad_trailing(label, 40)} #{:erlang.float_to_binary(mb, decimals: 2)}")
end

# ---- Component breakdown -----------------------------------------------

IO.puts("\n=== Component breakdown (medium ASCII input) ===")

medium = Map.fetch!(bench_inputs, "medium ASCII (10 words)")

bench = fn fun ->
  Enum.each(1..warmup_count, fn _ -> fun.() end)

  samples =
    for _ <- 1..measure_count do
      {us, _} = :timer.tc(fun)
      us
    end

  sorted = Enum.sort(samples)
  Enum.at(sorted, div(measure_count, 2))
end

stages = [
  {"Tokenizer.tokenize", fn -> Tokenizer.tokenize(medium) end},
  {"Features.extract", fn -> Features.extract(medium, model) end},
  {"Inference.compute_hidden",
   fn ->
     features = Features.extract(medium, model)
     Inference.compute_hidden(features, model.input_matrix)
   end},
  {"Inference.predict_features (k=1)",
   fn ->
     features = Features.extract(medium, model)
     Inference.predict_features(features, model, k: 1)
   end},
  {"Fasttext.detect (k=1)", fn -> Fasttext.detect(medium, model, k: 1) end}
]

IO.puts("stage                                   median (μs)")
IO.puts("--------------------------------------- -----------")

for {label, fun} <- stages do
  median = bench.(fun)
  IO.puts("#{String.pad_trailing(label, 39)} #{String.pad_leading(Integer.to_string(median), 11)}")
end

IO.puts("\n=== Done ===")
