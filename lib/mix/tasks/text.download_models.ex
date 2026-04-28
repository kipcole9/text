defmodule Mix.Tasks.Text.DownloadModels do
  @shortdoc "Downloads every model used by Text — fastText, sentiment, POS, NER"

  @moduledoc """
  Pre-downloads every external model used by `:text` so that subsequent
  calls run without network access.

  On-demand downloads work fine for development, but most production
  environments want every artefact present at boot. This task fetches:

  * `lid.176.bin` — fastText language identification (~126 MB), saved to
    `priv/lid_176/lid.176.bin` inside this project.

  * The default Hugging Face model used by `Text.Sentiment.Backends.Bumblebee`
    (XLM-RoBERTa, ~1.1 GB on first download) plus the tokenizer it
    actually loads (`FacebookAI/xlm-roberta-base`).

  * The default Hugging Face model used by `Text.POS` (English BERT,
    ~440 MB) plus its tokenizer (`google-bert/bert-base-uncased`).

  * The default Hugging Face model used by `Text.NER` (multilingual
    BERT, ~700 MB) plus its tokenizer (`google-bert/bert-base-multilingual-cased`).

  Hugging Face artefacts land in Bumblebee's cache directory
  (`~/.cache/bumblebee/` by default; override with `BUMBLEBEE_CACHE_DIR`
  or `XDG_CACHE_HOME`). Once cached, the corresponding `Text.*` modules
  load without any network round-trip.

  ## Usage

      mix text.download_models                  # download everything
      mix text.download_models --lid176         # just lid.176.bin
      mix text.download_models --sentiment      # just the sentiment stack
      mix text.download_models --pos --ner      # just POS + NER
      mix text.download_models --bumblebee      # all three Bumblebee stacks
      mix text.download_models --force          # re-download even if cached

  ## Options

  * `--lid176` — fetch `lid.176.bin` (or `lid.176.ftz` with `--quantized`).

  * `--sentiment` — fetch the default `Text.Sentiment.Backends.Bumblebee`
    model and tokenizer.

  * `--pos` — fetch the default `Text.POS` model and tokenizer.

  * `--ner` — fetch the default `Text.NER` model and tokenizer.

  * `--bumblebee` — shorthand for `--sentiment --pos --ner`.

  * `--all` — download every model. This is the default when no
    selection flag is given.

  * `--force` — re-download `lid.176.bin` even if a cached copy is
    already present. Bumblebee artefacts are cached by etag and
    refresh automatically when the upstream model updates, so this
    flag has no effect on the sentiment, POS, or NER stacks.

  * `--quantized` — only meaningful with `--lid176`; downloads the
    `.ftz` quantized variant instead of the full `.bin`.

  * `--model <repo>` — override the Hugging Face repo for the single
    selected model. Only valid when exactly one of `--sentiment`,
    `--pos`, or `--ner` is passed; mirrors the `:model` option each
    of those modules accepts.

  * `--tokenizer <repo>` — pair with `--model` to override the tokenizer
    repo as well.

  ### Bumblebee dependency

  Downloading the sentiment, POS, or NER models requires the optional
  `:bumblebee` dependency to be present in the host application. If
  it is missing, those steps are skipped with a warning; the
  fastText download still proceeds.

  """

  use Mix.Task

  alias Mix.Tasks.Text.DownloadModel

  # Single source of truth for the default model + tokenizer per stack.
  # Mirrors the `@default_model` / `@tokenizer_overrides` constants in
  # the corresponding `Text.*` modules; any change there should be
  # reflected here too.
  @bumblebee_stacks %{
    sentiment: %{
      module: Text.Sentiment.Backends.Bumblebee,
      model: "cardiffnlp/twitter-xlm-roberta-base-sentiment",
      tokenizer: "FacebookAI/xlm-roberta-base"
    },
    pos: %{
      module: Text.POS,
      model: "vblagoje/bert-english-uncased-finetuned-pos",
      tokenizer: "google-bert/bert-base-uncased"
    },
    ner: %{
      module: Text.NER,
      model: "Davlan/bert-base-multilingual-cased-ner-hrl",
      tokenizer: "google-bert/bert-base-multilingual-cased"
    }
  }

  @switches [
    lid176: :boolean,
    sentiment: :boolean,
    pos: :boolean,
    ner: :boolean,
    bumblebee: :boolean,
    all: :boolean,
    force: :boolean,
    quantized: :boolean,
    model: :string,
    tokenizer: :string
  ]

  @impl true
  def run(args) do
    {options, _rest, _invalid} = OptionParser.parse(args, switches: @switches)
    selection = expand_selection(options)

    if selection.lid176, do: download_lid176(options)
    if selection.sentiment, do: download_bumblebee_stack(:sentiment, options)
    if selection.pos, do: download_bumblebee_stack(:pos, options)
    if selection.ner, do: download_bumblebee_stack(:ner, options)

    :ok
  end

  # ---- selection ---------------------------------------------------------

  defp expand_selection(options) do
    explicit_flags = [:lid176, :sentiment, :pos, :ner, :bumblebee, :all]
    any_explicit? = Enum.any?(explicit_flags, &Keyword.get(options, &1, false))

    if any_explicit? do
      %{
        lid176: Keyword.get(options, :lid176, false) or Keyword.get(options, :all, false),
        sentiment:
          Keyword.get(options, :sentiment, false) or
            Keyword.get(options, :bumblebee, false) or
            Keyword.get(options, :all, false),
        pos:
          Keyword.get(options, :pos, false) or
            Keyword.get(options, :bumblebee, false) or
            Keyword.get(options, :all, false),
        ner:
          Keyword.get(options, :ner, false) or
            Keyword.get(options, :bumblebee, false) or
            Keyword.get(options, :all, false)
      }
    else
      # No selection flags → download everything.
      %{lid176: true, sentiment: true, pos: true, ner: true}
    end
  end

  # ---- lid.176 -----------------------------------------------------------

  defp download_lid176(options) do
    Mix.shell().info([:cyan, "→ fastText lid.176", :reset])

    forwarded =
      []
      |> maybe_forward(options, :force)
      |> maybe_forward(options, :quantized)

    DownloadModel.run(forwarded)
  end

  defp maybe_forward(args, options, key) do
    if Keyword.get(options, key, false) do
      args ++ ["--#{key}"]
    else
      args
    end
  end

  # ---- bumblebee stacks --------------------------------------------------

  defp download_bumblebee_stack(stack, options) do
    spec = resolve_stack_spec(stack, options)
    Mix.shell().info([:cyan, "→ #{label_for(stack)} (#{spec.model})", :reset])

    cond do
      not Code.ensure_loaded?(Bumblebee) ->
        Mix.shell().info([
          :yellow,
          "  skipped: :bumblebee dependency is not installed.\n",
          "  Add `{:bumblebee, \"~> 0.6\"}` (and `{:exla, \"~> 0.9\"}`) to mix.exs\n",
          "  to enable the #{label_for(stack)} stack.",
          :reset
        ])

      true ->
        # Make sure the HTTP/Finch stack used by Bumblebee is up.
        Application.ensure_all_started(:bumblebee)

        download_bumblebee_artefact(:model, spec.model, options)
        download_bumblebee_artefact(:tokenizer, spec.tokenizer, options)
    end
  end

  defp resolve_stack_spec(stack, options) do
    base = Map.fetch!(@bumblebee_stacks, stack)

    case {Keyword.get(options, :model), Keyword.get(options, :tokenizer)} do
      {nil, nil} ->
        base

      {model, nil} ->
        %{base | model: model, tokenizer: model}

      {nil, tokenizer} ->
        %{base | tokenizer: tokenizer}

      {model, tokenizer} ->
        %{base | model: model, tokenizer: tokenizer}
    end
  end

  defp label_for(:sentiment), do: "Sentiment (Bumblebee)"
  defp label_for(:pos), do: "POS (Bumblebee)"
  defp label_for(:ner), do: "NER (Bumblebee)"

  # `Bumblebee.load_model/2` and `load_tokenizer/2` populate the cache
  # as a side effect of loading; we discard the loaded artefact since
  # the goal is the on-disk cache, not the live struct.
  #
  # Bumblebee uses etag-based caching: an existing entry is kept iff
  # the upstream etag still matches, so a subsequent run picks up
  # upstream updates automatically. There is no explicit "force
  # re-download" knob — `--force` on this task therefore only affects
  # the fastText file (whose path we control directly).
  defp download_bumblebee_artefact(kind, repo, _options) do
    Mix.shell().info([:faint, "  · #{kind}: #{repo}", :reset])

    case load_artefact(kind, {:hf, repo}) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Mix.raise("Failed to download #{kind} #{repo}: #{inspect(reason)}")
    end
  end

  defp load_artefact(:model, repo_spec), do: Bumblebee.load_model(repo_spec)
  defp load_artefact(:tokenizer, repo_spec), do: Bumblebee.load_tokenizer(repo_spec)
end
