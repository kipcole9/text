defmodule Text.WordCloud.Backends.KeyBERT do
  @moduledoc """
  Neural keyword-extraction backend backed by
  [Bumblebee](https://hex.pm/packages/bumblebee).

  Implements [KeyBERT](https://github.com/MaartenGr/KeyBERT)-style
  scoring: embed the input document and each candidate phrase with a
  multilingual sentence-transformer, then rank candidates by cosine
  similarity to the document embedding. The intuition is that the
  best keyword candidates are the phrases whose meaning is closest
  to the document as a whole — exactly what neural sentence
  embeddings capture.

  This backend is **opt-in**:

  * The `:bumblebee` and (recommended) `:exla` Hex packages must be
    declared as dependencies of the host application.

  * Either pass `scoring: :key_bert` to `Text.WordCloud.terms/2`,
    or use this module directly.

  ### Cold start

  The first call downloads the default model (~470 MB —
  [`sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2`](https://huggingface.co/sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2),
  multilingual across ~50 languages) from Hugging Face, traces the
  inference graph, and compiles it under EXLA. Subsequent calls hit a
  cached `Nx.Serving` in `:persistent_term`. Pre-download via
  `mix text.download_models --keybert` if your production environment
  needs everything present at boot.

  ### When to use this backend

  KeyBERT typically produces the highest-quality output of any
  backend in this package — at the cost of a model download, GPU/EXLA
  compilation, and substantially higher per-call latency than YAKE!
  Use this when quality matters more than throughput, or when YAKE!'s
  statistical features struggle with very short or very domain-specific
  text.

  ### Options

  * `:model` — Hugging Face model id. Defaults to
    `"sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"`.
    Any sentence-transformer model compatible with
    `Bumblebee.Text.text_embedding/3` works.

  * `:tokenizer_repo` — overrides the tokenizer source repo (rarely
    needed for sentence-transformer models, which ship complete
    tokenizers).

  * `:serving` — name or pid of a pre-started `Nx.Serving` to skip
    the lazy `:persistent_term` cache. Recommended for production.

  * `:candidate_pool_size` — cap on the number of candidates
    embedded; large documents can produce hundreds of phrases and
    embedding all of them is wasteful. Defaults to `200`. Candidates
    are pre-filtered by raw frequency before embedding.

  * `:ngram_range` — `{min, max}` candidate length. Defaults to
    `{1, 3}`.

  Standard `Text.WordCloud` orchestrator options (`:language`,
  `:stopwords`, `:case_fold`, `:locale`) are honoured.

  """

  alias Text.WordCloud.Tokens

  @default_model "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
  @default_pool 200

  if Code.ensure_loaded?(Bumblebee) do
    @behaviour Text.WordCloud.Backend

    @impl true
    def score(input, options) do
      {min_n, max_n} = Keyword.get(options, :ngram_range, {1, 3})
      pool_size = Keyword.get(options, :candidate_pool_size, @default_pool)

      %{sentences: sentences} = Tokens.prepare(input, options)

      # Build the candidate pool: top-N by frequency, to keep the
      # number of model calls bounded.
      candidates =
        sentences
        |> Tokens.candidates(min_n, max_n)
        |> Tokens.count_candidates()
        |> Enum.sort_by(fn {_t, count, _kind} -> -count end)
        |> Enum.take(pool_size)

      if candidates == [] do
        []
      else
        score_candidates(input_text(input), candidates, options)
      end
    end

    defp score_candidates(text, candidates, options) do
      serving = resolve_serving(options)

      doc_embedding = embed!(serving, [text]) |> hd()
      candidate_texts = Enum.map(candidates, fn {tokens, _c, _k} -> Enum.join(tokens, " ") end)
      candidate_embeddings = embed!(serving, candidate_texts)

      candidates
      |> Enum.zip(candidate_embeddings)
      |> Enum.map(fn {{tokens, count, kind}, embedding} ->
        score = cosine_similarity(doc_embedding, embedding)
        # Cosine sim is in [-1, 1]; shift to [0, 2] so the orchestrator's
        # max-normalisation produces sensible relative weights even when
        # the top candidate has only modest similarity.
        {Enum.join(tokens, " "), score + 1.0, count, kind}
      end)
    end

    # ---- internal: serving cache --------------------------------------

    defp resolve_serving(options) do
      case Keyword.get(options, :serving) do
        nil ->
          model = Keyword.get(options, :model, @default_model)
          cache_key = {__MODULE__, :serving, model}

          case :persistent_term.get(cache_key, nil) do
            nil ->
              serving = build_serving(model, options)
              :persistent_term.put(cache_key, serving)
              serving

            serving ->
              serving
          end

        serving ->
          serving
      end
    end

    defp build_serving(model, options) do
      defn_options = Keyword.get(options, :defn_options, default_defn_options())
      compile = Keyword.get(options, :compile, batch_size: 16, sequence_length: 128)
      tokenizer_repo = Keyword.get(options, :tokenizer_repo, model)

      {:ok, model_info} = Bumblebee.load_model({:hf, model})
      {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, tokenizer_repo})

      Bumblebee.Text.text_embedding(model_info, tokenizer,
        compile: compile,
        defn_options: defn_options,
        output_attribute: :hidden_state,
        output_pool: :mean_pooling
      )
    end

    defp default_defn_options do
      if Code.ensure_loaded?(EXLA), do: [compiler: EXLA], else: []
    end

    # ---- internal: embedding + similarity -----------------------------

    defp embed!(serving, texts) when is_list(texts) do
      texts
      |> Enum.map(fn text -> Nx.Serving.run(serving, text).embedding end)
    end

    defp cosine_similarity(a, b) do
      dot = a |> Nx.dot(b) |> Nx.to_number()
      norm_a = a |> Nx.pow(2) |> Nx.sum() |> Nx.sqrt() |> Nx.to_number()
      norm_b = b |> Nx.pow(2) |> Nx.sum() |> Nx.sqrt() |> Nx.to_number()
      denom = norm_a * norm_b

      if denom == 0.0, do: 0.0, else: dot / denom
    end

    defp input_text(text) when is_binary(text), do: text
    defp input_text([_ | _] = docs), do: Enum.join(docs, "\n")

    @doc """
    Drops the cached `Nx.Serving` for the given KeyBERT model.

    ### Arguments

    * `model` — a model id string. Defaults to the package default.
      Pass `:all` to drop every cached serving for this backend.

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
    def score(_input, _options) do
      raise """
      Text.WordCloud.Backends.KeyBERT requires the :bumblebee dependency.

      Add to your mix.exs:

          {:bumblebee, "~> 0.6"},
          {:exla, "~> 0.9"}

      Then run `mix deps.get`. See the Text.WordCloud.Backends.KeyBERT
      moduledoc for usage.
      """
    end
  end
end
