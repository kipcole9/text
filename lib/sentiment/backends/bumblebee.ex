defmodule Text.Sentiment.Backends.Bumblebee do
  @moduledoc """
  Neural sentiment backend backed by
  [Bumblebee](https://hex.pm/packages/bumblebee).

  Loads a pre-trained multilingual sentiment classifier from Hugging
  Face and serves predictions via `Nx.Serving`. The default model is
  [`cardiffnlp/twitter-xlm-roberta-base-sentiment`](https://huggingface.co/cardiffnlp/twitter-xlm-roberta-base-sentiment),
  an XLM-RoBERTa model fine-tuned on multilingual Twitter data
  (English, French, German, Italian, Spanish, Portuguese, Arabic, and
  Hindi by training, with reasonable transfer to many more languages
  via the underlying multilingual base).

  This backend is **opt-in**:

  * The `:bumblebee` and `:exla` Hex packages must be added as
    dependencies of the host application.

  * Either pass `backend: Text.Sentiment.Backends.Bumblebee` to
    `Text.Sentiment.analyze/2`, or set the application config:

        config :text, :sentiment_backend, Text.Sentiment.Backends.Bumblebee

  ### Cold start

  The first call to `analyze/2` downloads the model weights (~280 MB
  on disk) from Hugging Face, traces the inference graph through
  Bumblebee, and compiles it under EXLA (or `Nx.Defn.Evaluator` if
  EXLA is not loaded). Expect a 10–30 second cold start. Subsequent
  calls in the same VM run in single-digit milliseconds — the compiled
  serving is cached in `:persistent_term`.

  For production deployments where cold start is unacceptable, start
  a named serving process at boot via
  `Bumblebee.Text.text_classification/3` + `Nx.Serving.start_link/1`,
  then pass `serving: <name_or_pid>` to `analyze/2` to skip the cache
  entirely.

  ### Tokenizer override

  Some fine-tuned models on Hugging Face ship without the
  `tokenizer.json` Bumblebee expects — they have only the raw
  SentencePiece or WordPiece data. The default Cardiff sentiment
  model is one of those, so this backend loads its tokenizer from
  the base `FacebookAI/xlm-roberta-base` repo instead. Other models
  fall through to "use the same repo as the model" by default.

  If you point `:model` at a fine-tune that itself lacks a
  `tokenizer.json`, pass `:tokenizer_repo` to point at a repo that
  has one (typically the base model the fine-tune was trained on).

  ### Result shape

  Returns the same map shape every backend produces:

  * `:label` — `:positive`, `:negative`, or `:neutral` (mapped from
    the model's textual labels).

  * `:compound` — `P(positive) − P(negative)`, in `[-1.0, +1.0]`.

  * `:scores` — the full per-label probability map, e.g.
    `%{positive: 0.86, neutral: 0.10, negative: 0.04}`.

  * `:backend` — `Text.Sentiment.Backends.Bumblebee`.

  * `:model` — the model id used for the prediction.

  Unlike the lexicon backend, no `:matched`/`:tokens` counts are
  included — the underlying model is opaque about which tokens it used.

  ### Language

  XLM-RoBERTa is intrinsically multilingual; no per-language routing
  is required. The `:language` option is accepted (for API consistency
  with the lexicon backend) but ignored by this backend; the language
  used at scoring time is reported in the result map for round-tripping.

  """

  if Code.ensure_loaded?(Bumblebee) do
    @behaviour Text.Sentiment.Backend

    @default_model "cardiffnlp/twitter-xlm-roberta-base-sentiment"

    # The Cardiff sentiment fine-tune ships `sentencepiece.bpe.model`
    # but not the `tokenizer.json` Bumblebee currently expects, so the
    # tokenizer has to be loaded from the base XLM-RoBERTa repo
    # instead. The mapping is per-model — for any other repo we fall
    # through to "load the tokenizer from the same repo as the model".
    @tokenizer_overrides %{
      "cardiffnlp/twitter-xlm-roberta-base-sentiment" => "FacebookAI/xlm-roberta-base"
    }

    @impl true
    def analyze(text, options \\ []) when is_binary(text) do
      serving = resolve_serving(options)
      %{predictions: predictions} = Nx.Serving.run(serving, text)

      scores = predictions_to_scores(predictions)
      pos = Map.get(scores, :positive, 0.0)
      neg = Map.get(scores, :negative, 0.0)
      compound = pos - neg
      label = top_label(predictions)
      thresholds = label_thresholds(options)

      %{
        label: label_with_thresholds(label, compound, thresholds),
        compound: compound,
        scores: scores,
        backend: __MODULE__,
        model: model_id(options),
        language:
          options
          |> Keyword.get(:language)
          |> normalize_language()
      }
    end

    # ---- internal: serving cache ----------------------------------------

    defp resolve_serving(options) do
      cond do
        serving = Keyword.get(options, :serving) ->
          serving

        true ->
          model = model_id(options)
          cache_key = {__MODULE__, :serving, model}

          case :persistent_term.get(cache_key, nil) do
            nil ->
              serving = build_serving(model, options)
              :persistent_term.put(cache_key, serving)
              serving

            serving ->
              serving
          end
      end
    end

    defp build_serving(model, options) do
      defn_options = Keyword.get(options, :defn_options, default_defn_options())
      compile = Keyword.get(options, :compile, batch_size: 1, sequence_length: 128)
      tokenizer_repo = resolve_tokenizer_repo(model, options)

      {:ok, model_info} = Bumblebee.load_model({:hf, model})
      {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, tokenizer_repo})

      Bumblebee.Text.text_classification(model_info, tokenizer,
        compile: compile,
        defn_options: defn_options,
        scores_function: :softmax
      )
    end

    defp resolve_tokenizer_repo(model, options) do
      Keyword.get(options, :tokenizer_repo) || Map.get(@tokenizer_overrides, model, model)
    end

    defp default_defn_options do
      if Code.ensure_loaded?(EXLA), do: [compiler: EXLA], else: []
    end

    defp model_id(options), do: Keyword.get(options, :model, @default_model)

    # ---- internal: result shaping --------------------------------------

    defp predictions_to_scores(predictions) do
      Map.new(predictions, fn %{label: label, score: score} ->
        {label_to_atom(label), score}
      end)
    end

    defp top_label(predictions) do
      predictions
      |> Enum.max_by(& &1.score)
      |> Map.fetch!(:label)
      |> label_to_atom()
    end

    # The Cardiff XLM-RoBERTa model uses lowercase string labels
    # ("positive", "negative", "neutral"). Normalise to the same
    # atoms the lexicon backend emits.
    defp label_to_atom("positive"), do: :positive
    defp label_to_atom("negative"), do: :negative
    defp label_to_atom("neutral"), do: :neutral
    defp label_to_atom("LABEL_0"), do: :negative
    defp label_to_atom("LABEL_1"), do: :neutral
    defp label_to_atom("LABEL_2"), do: :positive
    defp label_to_atom(other) when is_binary(other), do: String.to_atom(String.downcase(other))

    # The model's argmax label and the compound-score-derived label can
    # disagree near the threshold — when the top-scoring class is
    # `:neutral` but `compound` is far from zero, prefer compound for
    # consistency with the lexicon backend's threshold logic.
    defp label_with_thresholds(top_label, compound, {pos_t, neg_t}) do
      cond do
        compound >= pos_t -> :positive
        compound <= neg_t -> :negative
        top_label == :positive and compound < pos_t -> :neutral
        top_label == :negative and compound > neg_t -> :neutral
        true -> top_label
      end
    end

    defp label_thresholds(options) do
      pos = Keyword.get(options, :positive_threshold, 0.05)
      neg = Keyword.get(options, :negative_threshold, -0.05)
      {pos, neg}
    end

    defp normalize_language(nil), do: nil

    defp normalize_language(input) do
      Text.Language.normalize(input)
    rescue
      FunctionClauseError -> nil
    end

    @doc """
    Drops the cached `Nx.Serving` for the given model (or all models).

    Useful in tests, or when switching defn-options at runtime.

    ### Arguments

    * `model` — a model id string. Defaults to the package default
      (`#{@default_model}`). Pass `:all` to drop every cached
      serving.

    ### Returns

    * `:ok`.

    """
    @spec reset(String.t() | :all) :: :ok
    def reset(model \\ @default_model)

    def reset(:all) do
      :persistent_term.get()
      |> Enum.each(fn
        {{__MODULE__, :serving, _model}, _value} = entry ->
          :persistent_term.erase(elem(entry, 0))

        _ ->
          :ok
      end)
    end

    def reset(model) when is_binary(model) do
      _ = :persistent_term.erase({__MODULE__, :serving, model})
      :ok
    end
  else
    def analyze(_text, _options \\ []) do
      raise """
      Text.Sentiment.Backends.Bumblebee requires the :bumblebee dependency.

      Add it to your mix.exs:

          {:bumblebee, "~> 0.6"},
          {:exla, "~> 0.9"}

      Then run `mix deps.get`. See the Text.Sentiment.Backends.Bumblebee
      moduledoc for usage.
      """
    end
  end
end
