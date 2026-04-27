defmodule Text.Language.Classifier.Fasttext do
  @moduledoc """
  Pure-Elixir port of fastText's `lid.176` language identification model.

  This module is the public entry point for the fastText classifier. It
  glues together the lower-level pieces — `ModelLoader`, `Features`,
  `Inference`, `ScriptDetector`, `Locale` — into a small API for
  end users.

  ### Loading a model

  The `lid.176.bin` model file is approximately 126 MB and is **not**
  shipped with this package. Fetch it once after installing the library:

      mix text.download_model

  Then load it at application startup:

      {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load(
        Path.join(:code.priv_dir(:text), "lid_176/lid.176.bin")
      )

  Loaded models are immutable and safe to share across processes — the
  matrices live in `Nx` tensors backed by reference-counted refcs, so
  passing the struct between processes does not duplicate the 128 MB
  payload.

  ### Detecting a language

      iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load("priv/lid_176/lid.176.bin")
      iex> {:ok, det} = Text.Language.Classifier.Fasttext.detect("Bonjour le monde", model)
      iex> det.language
      "fr"
      iex> det.script
      :Latn
      iex> det.confidence > 0.9
      true

  ### Just the language code

      iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load("priv/lid_176/lid.176.bin")
      iex> Text.Language.Classifier.Fasttext.classify("Hola mundo", model)
      {:ok, "es"}

  ### Resolving to a CLDR locale

  When the [`localize`](https://hex.pm/packages/localize) optional
  dependency is available, detections can be expanded into full
  CLDR-canonical locale strings via likely-subtags:

      iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load("priv/lid_176/lid.176.bin")
      iex> {:ok, det} = Text.Language.Classifier.Fasttext.detect("你好世界", model)
      iex> {:ok, locale} = Text.Language.Classifier.Fasttext.to_locale(det)
      iex> String.starts_with?(locale, "zh")
      true

  Without `localize`, a small built-in fallback table covers the most
  common languages.

  ### Confidence and uncertainty

  fastText assigns a probability to every label. For very short or
  ambiguous inputs the top-1 confidence may be modest. Callers that need
  to gate on confidence should inspect `Detection.confidence` directly:

      case Text.Language.Classifier.Fasttext.detect(text, model) do
        {:ok, %{confidence: c, language: lang}} when c > 0.7 ->
          {:ok, lang}
        {:ok, _} ->
          {:uncertain, "confidence below threshold"}
      end

  """

  alias Text.Language.Classifier.Fasttext.{Detection, Inference, Locale, Model, ScriptDetector}

  @default_top_k 5

  @doc """
  Runs fastText language identification on `text` and returns a
  detection struct with the language, script, confidence, and
  alternatives.

  ### Arguments

  * `text` is a UTF-8 binary.

  * `model` is a loaded `Text.Language.Classifier.Fasttext.Model`.

  ### Options

  * `:k` — number of top predictions to record. The first becomes the
    main detection; the rest become `alternatives`. Defaults to
    `#{@default_top_k}`.

  * `:threshold` — drop predictions below this probability. Defaults
    to `0.0` (matches fastText's Python wrapper).

  ### Returns

  * `{:ok, detection}` where `detection` is a
    `Text.Language.Classifier.Fasttext.Detection` struct.

  * `{:error, :no_predictions}` when the model produces no candidate at
    all (which only happens if `:threshold` is set high enough to drop
    every label). Empty or whitespace-only input is **not** an error —
    fastText still produces a low-confidence prediction in that case
    (matching the reference's Python wrapper).

  ### Examples

      iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load("priv/lid_176/lid.176.bin")
      iex> {:ok, det} = Text.Language.Classifier.Fasttext.detect("Hello world", model)
      iex> det.language
      "en"

  """
  @spec detect(binary(), Model.t(), keyword()) ::
          {:ok, Detection.t()} | {:error, atom()}
  def detect(text, %Model{} = model, options \\ []) when is_binary(text) do
    k = Keyword.get(options, :k, @default_top_k)
    threshold = Keyword.get(options, :threshold, 0.0)

    case Inference.predict(text, model, k: k, threshold: threshold) do
      [] ->
        {:error, :no_predictions}

      [{language, confidence} | rest] ->
        detection = %Detection{
          language: language,
          confidence: confidence,
          script: ScriptDetector.detect(text),
          alternatives: rest,
          text: text
        }

        {:ok, detection}
    end
  end

  @doc """
  Convenience wrapper that returns just the top-1 language code.

  ### Arguments

  * `text` is a UTF-8 binary.

  * `model` is a loaded `Text.Language.Classifier.Fasttext.Model`.

  ### Returns

  * `{:ok, language}` where `language` is a BCP-47 language subtag.

  * `{:error, :empty_input}` for empty inputs.

  ### Examples

      iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load("priv/lid_176/lid.176.bin")
      iex> Text.Language.Classifier.Fasttext.classify("Привет мир", model)
      {:ok, "ru"}

  """
  @spec classify(binary(), Model.t()) :: {:ok, String.t()} | {:error, atom()}
  def classify(text, %Model{} = model) when is_binary(text) do
    case detect(text, model, k: 1) do
      {:ok, %Detection{language: language}} -> {:ok, language}
      {:error, _} = error -> error
    end
  end

  @doc """
  Resolves a `Detection` into a canonical CLDR locale string.

  Delegates to `Text.Language.Classifier.Fasttext.Locale.resolve/2`. See
  that module for the resolution algorithm and the available options.

  ### Examples

      iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load("priv/lid_176/lid.176.bin")
      iex> {:ok, det} = Text.Language.Classifier.Fasttext.detect("Hola, ¿cómo estás?", model)
      iex> {:ok, locale} = Text.Language.Classifier.Fasttext.to_locale(det, region: :MX)
      iex> String.contains?(locale, "MX")
      true

  """
  @spec to_locale(Detection.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def to_locale(%Detection{} = detection, options \\ []) do
    Locale.resolve(detection, options)
  end
end
