# Benchmark for the fastText `lid.176` inference path.
#
# Run with:
#
#     mix text.download_model       # one-time, fetches lid.176.bin
#     mix run bench/fasttext_inference.exs
#
# The benchmark loads the model once (taking 1-2 seconds and ~128 MB of
# RSS) then exercises the hot inference path on inputs of varying length
# and script. Results are reported per-prediction (warm) so the model
# load cost is not amortised in.

alias Text.Language.Classifier.Fasttext
alias Text.Language.Classifier.Fasttext.{Features, Inference, ModelLoader, Tokenizer}

model_path =
  Path.join([
    File.cwd!(),
    "priv",
    "lid_176",
    "lid.176.bin"
  ])

unless File.exists?(model_path) do
  Mix.shell().error("""
  lid.176.bin not found at #{model_path}.
  Run `mix text.download_model` first.
  """)

  System.halt(1)
end

IO.puts("Loading #{model_path}...")
{load_us, {:ok, model}} = :timer.tc(fn -> ModelLoader.load(model_path) end)
IO.puts("Loaded in #{Float.round(load_us / 1000, 1)} ms")
IO.puts("nwords=#{model.dictionary.nwords} bucket=#{model.args.bucket} dim=#{model.args.dim}")

# A small spread of input shapes — short ASCII, long ASCII, mixed-script,
# and CJK — covers the common variation in tokenization cost.
inputs = %{
  "short ASCII (3 words)" => "the cat sat",
  "medium ASCII (10 words)" => "the quick brown fox jumps over the lazy dog now",
  "long ASCII (~80 chars)" =>
    "Hello world. This is an English sentence used for language identification testing.",
  "mixed-script" =>
    "Привет мир, hello world, 你好世界, مرحبا بالعالم.",
  "CJK (Chinese)" => "这是一个用于语言识别的中文句子。",
  "CJK (Japanese)" => "これは言語識別のための日本語の文です。",
  "Cyrillic (Russian)" => "Это русское предложение для определения языка."
}

Benchee.run(
  %{
    "tokenize" => fn input -> Tokenizer.tokenize(input) end,
    "Features.extract" => fn input -> Features.extract(input, model) end,
    "Inference.predict (k=1)" => fn input -> Inference.predict(input, model, k: 1) end,
    "Inference.predict (k=5)" => fn input -> Inference.predict(input, model, k: 5) end,
    "Fasttext.detect (k=5)" => fn input -> Fasttext.detect(input, model, k: 5) end,
    "Fasttext.detect + to_locale" => fn input ->
      {:ok, det} = Fasttext.detect(input, model)
      {:ok, _locale} = Fasttext.to_locale(det)
    end
  },
  inputs: inputs,
  warmup: 1,
  time: 3,
  memory_time: 1,
  print: [fast_warning: false]
)
