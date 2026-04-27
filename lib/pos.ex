defmodule Text.POS do
  @moduledoc """
  Part-of-speech tagging via [Bumblebee](https://hex.pm/packages/bumblebee).

  Exposes `tag/2` which assigns a part-of-speech label
  (`:noun`, `:verb`, `:adj`, …) to every word in an input sentence.
  Backed by a pre-trained transformer loaded through Bumblebee's
  `token_classification/3` serving — the default model is
  [`vblagoje/bert-english-uncased-finetuned-pos`](https://huggingface.co/vblagoje/bert-english-uncased-finetuned-pos),
  trained on the OntoNotes 5.0 / Penn Treebank tag set.

  ### Optional dependency

  POS tagging requires the `:bumblebee` and (recommended) `:exla`
  Hex packages. They are declared as optional dependencies of
  `:text`; add them to your application's `mix.exs` to enable this
  module:

      {:bumblebee, "~> 0.6"},
      {:exla, "~> 0.9"}

  Without `:bumblebee`, calling `tag/2` raises with a clear "add
  these to your deps" message.

  ### Cold start and caching

  The first call to `tag/2` downloads the model (~440 MB for the
  default English model) from Hugging Face, traces the inference
  graph, and compiles it under EXLA. Subsequent calls hit a cached
  `Nx.Serving` in `:persistent_term` and run in single-digit
  milliseconds.

  For production, prefer starting a named serving at boot:

      serving = Bumblebee.Text.token_classification(model_info, tokenizer)
      {:ok, _pid} = Nx.Serving.start_link(serving: serving, name: MyApp.POS)

      Text.POS.tag("the cat sat", serving: MyApp.POS)

  ### Result shape

  `tag/2` returns a list of `{token, tag, score}` triples. The
  `tag` is an atom drawn from the model's label set — for the
  default English model that's the Penn Treebank-derived
  `:noun, :verb, :adj, :adv, :pron, :det, :punct, …`.

  ### Languages

  The default model is English-only. For multilingual POS, supply
  a `:model` option pointing to a multilingual checkpoint — for
  example, `"QCRI/bert-base-multilingual-cased-pos-english"` for
  English, or one of the language-specific BERT POS models on
  Hugging Face. The result shape is the same; only the tag
  vocabulary changes.

  """

  @default_model "vblagoje/bert-english-uncased-finetuned-pos"

  @typedoc "A single token-and-tag entry in the result list."
  @type tagged_token :: {String.t(), atom(), float()}

  if Code.ensure_loaded?(Bumblebee) do
    @doc """
    Returns the part-of-speech tags for `text`.

    ### Arguments

    * `text` is a UTF-8 binary.

    ### Options

    * `:model` — the Hugging Face model id to use. Defaults to
      `"#{@default_model}"`. Any sequence-tagging checkpoint
      compatible with `Bumblebee.Text.token_classification/3`
      works.

    * `:serving` — pass a name or pid of a pre-started `Nx.Serving`
      to skip the lazy `:persistent_term` cache. Useful in
      production, especially for sharing a single serving across an
      application.

    * `:compile` — defn-compilation options for the model. Defaults
      to `[batch_size: 1, sequence_length: 128]`.

    ### Returns

    * A list of `{token, tag, score}` triples.

    """
    @spec tag(String.t(), keyword()) :: [tagged_token()]
    def tag(text, options \\ []) when is_binary(text) do
      serving = resolve_serving(options)
      %{entities: entities} = Nx.Serving.run(serving, text)

      Enum.map(entities, fn entity ->
        {entity.phrase, label_to_atom(entity.label), entity.score}
      end)
    end

    @doc """
    Drops the cached `Nx.Serving` for the given model (or all models).
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

    # ---- internal -----------------------------------------------------

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
      compile = Keyword.get(options, :compile, [batch_size: 1, sequence_length: 128])
      defn_options = Keyword.get(options, :defn_options, default_defn_options())

      {:ok, model_info} = Bumblebee.load_model({:hf, model})
      {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model})

      Bumblebee.Text.token_classification(model_info, tokenizer,
        compile: compile,
        defn_options: defn_options,
        aggregation: :same
      )
    end

    defp default_defn_options do
      if Code.ensure_loaded?(EXLA), do: [compiler: EXLA], else: []
    end

    # Penn Treebank / OntoNotes tags are uppercase strings ("NN",
    # "NNS", "VB", "VBD", ...). Map to coarser atoms for ergonomics;
    # callers needing the fine-grained tag can use the model's raw
    # label by reaching into the underlying serving directly.
    defp label_to_atom(label) when is_binary(label) do
      cond do
        String.starts_with?(label, "NN") -> :noun
        String.starts_with?(label, "VB") -> :verb
        String.starts_with?(label, "JJ") -> :adj
        String.starts_with?(label, "RB") -> :adv
        String.starts_with?(label, "PRP") -> :pron
        String.starts_with?(label, "DT") -> :det
        label in ["IN", "TO"] -> :prep
        label in ["CC"] -> :conj
        label in ["UH"] -> :interj
        label in ["CD"] -> :num
        label in ["MD"] -> :modal
        label in [".", ",", ":", "(", ")", "``", "''"] -> :punct
        true -> label |> String.downcase() |> String.to_atom()
      end
    end
  else
    def tag(_text, _options \\ []) do
      raise """
      Text.POS.tag/2 requires the :bumblebee dependency.

      Add to your mix.exs:

          {:bumblebee, "~> 0.6"},
          {:exla, "~> 0.9"}

      Then run `mix deps.get`.
      """
    end
  end
end
