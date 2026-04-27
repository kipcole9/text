defmodule Text.NER do
  @moduledoc """
  Named-entity recognition via [Bumblebee](https://hex.pm/packages/bumblebee).

  Identifies named entities (people, organisations, locations, …) in
  natural-language text and returns each as a span with type and
  confidence. Backed by Bumblebee's
  `Bumblebee.Text.token_classification/3` serving with span
  aggregation, loading a pre-trained transformer from Hugging Face.

  ### Default model

  The default is
  [`Davlan/bert-base-multilingual-cased-ner-hrl`](https://huggingface.co/Davlan/bert-base-multilingual-cased-ner-hrl),
  trained on 10 high-resource languages (Arabic, German, English,
  Spanish, French, Italian, Latvian, Dutch, Portuguese, Chinese)
  with the standard four-class CoNLL-2003 tag set:

  * `:per` — person
  * `:org` — organisation
  * `:loc` — location
  * `:misc` — miscellaneous

  Override with `:model` to use a language-specific or
  domain-specific NER model.

  ### Optional dependency

  Like `Text.POS`, NER requires the optional `:bumblebee` and
  `:exla` Hex packages. Without `:bumblebee`, `extract/2` raises
  with a helpful message.

  ### Cold start and caching

  First call downloads the model (~700 MB for the multilingual
  default) and traces the inference graph. Subsequent calls hit a
  `:persistent_term`-cached serving. For production, start a named
  serving at boot:

      serving = Bumblebee.Text.token_classification(model_info, tokenizer,
                  aggregation: :same)
      {:ok, _pid} = Nx.Serving.start_link(serving: serving, name: MyApp.NER)

      Text.NER.extract(text, serving: MyApp.NER)

  ### Result shape

      %Text.NER.Entity{
        text: "Barack Obama",
        type: :per,
        start: 0,
        end: 12,
        score: 0.99
      }

  Spans are byte offsets into the original input.

  """

  defmodule Entity do
    @moduledoc """
    A single named entity span.

    ### Fields

    * `text` — the span's surface text, exactly as it appeared in
      the input.

    * `type` — the entity category. Atoms drawn from the model's
      label set; the default model uses `:per`, `:org`, `:loc`, or
      `:misc`.

    * `start`, `end` — byte offsets of the span within the input.

    * `score` — the model's confidence in `[0.0, 1.0]`.

    """
    @type t :: %__MODULE__{
            text: String.t(),
            type: atom(),
            start: non_neg_integer(),
            end: non_neg_integer(),
            score: float()
          }

    defstruct [:text, :type, :start, :end, :score]
  end

  @default_model "Davlan/bert-base-multilingual-cased-ner-hrl"

  if Code.ensure_loaded?(Bumblebee) do
    @doc """
    Extracts named entities from `text`.

    ### Arguments

    * `text` is a UTF-8 binary.

    ### Options

    * `:model` — the Hugging Face model id. Defaults to the
      multilingual `"#{@default_model}"`.

    * `:serving` — pass a name or pid of a pre-started `Nx.Serving`
      to skip the lazy cache.

    * `:compile` — defn-compilation options. Defaults to
      `[batch_size: 1, sequence_length: 256]`.

    * `:min_score` — filter out entities below this confidence.
      Defaults to `0.0` (keep everything).

    ### Returns

    * A list of `Text.NER.Entity` structs in document order.

    """
    @spec extract(String.t(), keyword()) :: [Entity.t()]
    def extract(text, options \\ []) when is_binary(text) do
      serving = resolve_serving(options)
      min_score = Keyword.get(options, :min_score, 0.0)

      %{entities: entities} = Nx.Serving.run(serving, text)

      entities
      |> Enum.filter(fn e -> e.score >= min_score end)
      |> Enum.map(&to_entity/1)
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
      compile = Keyword.get(options, :compile, [batch_size: 1, sequence_length: 256])
      defn_options = Keyword.get(options, :defn_options, default_defn_options())
      tokenizer_repo = Keyword.get(options, :tokenizer_repo, model)

      {:ok, model_info} = Bumblebee.load_model({:hf, model})
      {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, tokenizer_repo})

      Bumblebee.Text.token_classification(model_info, tokenizer,
        compile: compile,
        defn_options: defn_options,
        aggregation: :same
      )
    end

    defp default_defn_options do
      if Code.ensure_loaded?(EXLA), do: [compiler: EXLA], else: []
    end

    defp to_entity(raw) do
      %Entity{
        text: raw.phrase,
        type: type_to_atom(raw.label),
        start: raw.start,
        end: raw.end,
        score: raw.score
      }
    end

    # CoNLL-style labels are uppercase ("PER", "ORG", "LOC", "MISC")
    # often prefixed with B-/I- for span boundaries (handled by
    # Bumblebee's `aggregation: :same`). Normalise to lowercase atoms.
    defp type_to_atom(label) when is_binary(label) do
      label |> String.downcase() |> String.to_atom()
    end
  else
    def extract(_text, _options \\ []) do
      raise """
      Text.NER.extract/2 requires the :bumblebee dependency.

      Add to your mix.exs:

          {:bumblebee, "~> 0.6"},
          {:exla, "~> 0.9"}

      Then run `mix deps.get`.
      """
    end
  end
end
