defmodule Text.Language.Classifier.Fasttext.Inference do
  @moduledoc """
  Forward-pass scoring for fastText models.

  Given a flat list of input-matrix row indices (produced by
  `Text.Language.Classifier.Fasttext.Features.extract/2`), this module
  computes a hidden vector and projects it to a list of `{label, probability}`
  pairs, sorted descending by probability.

  Two output projections are supported:

  * `:softmax` — `softmax(output_matrix · hidden)`. The standard form.

  * `:hs` (hierarchical softmax) — root-to-leaf DFS over the Huffman tree
    built at load time. Each internal node carries a learned vector in
    `output_matrix[node - osz]`; the score of a leaf is the sum of
    `log(sigmoid(±dot))` decisions along its path. This is the projection
    `lid.176` uses.

  Mirrors `Model::predict` and `HierarchicalSoftmaxLoss::dfs` from the
  fastText source (`src/model.cc`, `src/loss.cc`).

  ### Numerical conventions

  fastText uses `std_log(x) = log(x + 1e-5)` instead of plain `log(x)` for
  numerical stability when probabilities approach zero. This module uses
  the same.

  Top-k pruning during DFS matches the C++ heap-based approach: a branch
  is skipped once its accumulated score drops below the lowest score
  currently in the top-k buffer. For a small model like `lid.176` (176
  leaves) the speedup is modest, but it preserves bit-equivalence with
  the reference's traversal order.

  """

  import Nx.Defn

  alias Text.Language.Classifier.Fasttext.{Features, HuffmanTree, Model}

  @log_epsilon 1.0e-5
  @eos_token "</s>"

  # ---- fused tensor pipelines (defn) -------------------------------------
  #
  # The Nx ops `take` → `mean` → `dot` (and the softmax tail) are folded
  # into single `defn` graphs so an EXLA-compiled execution runs the
  # whole forward pass as one kernel call rather than 4–8 separate
  # BEAM ↔ NIF round trips. Without this, EXLA's per-call overhead
  # (~10 µs each) dominates the per-prediction wall time on small
  # models like `lid.176`.
  #
  # Both functions are also valid under the default `Nx.Defn.Evaluator`
  # compiler, so the package still works correctly when EXLA is not
  # installed — the savings simply don't materialise.

  defnp hidden_n(feature_indices, input_matrix) do
    rows = Nx.take(input_matrix, feature_indices, axis: 0)
    Nx.mean(rows, axes: [0])
  end

  defnp logits_n(feature_indices, input_matrix, output_matrix) do
    Nx.dot(output_matrix, hidden_n(feature_indices, input_matrix))
  end

  defnp softmax_probs_n(feature_indices, input_matrix, output_matrix) do
    logits = logits_n(feature_indices, input_matrix, output_matrix)
    shifted = logits - Nx.reduce_max(logits)
    exps = Nx.exp(shifted)
    exps / Nx.sum(exps)
  end

  # Vectorised hierarchical softmax. Replaces the BEAM-side recursive
  # DFS with one fused EXLA pipeline:
  #
  #   1. Compute the hidden vector (`take + mean`).
  #   2. Project onto the output matrix to get `internal_dots`.
  #   3. For every leaf, look up its path's internal-node dots,
  #      multiply by `±1` direction signs, and sum the per-step
  #      `log(sigmoid(signed_dot) + epsilon)` contributions, masking
  #      out padding positions.
  #
  # The result is a `{nlabels}` vector of leaf log-probabilities,
  # ready for BEAM-side top-K selection.
  defnp hs_log_probs_n(feature_indices, input_matrix, output_matrix, paths, signs, mask) do
    dots = logits_n(feature_indices, input_matrix, output_matrix)
    signed = Nx.take(dots, paths) * signs
    sigmoids = 1.0 / (1.0 + Nx.exp(-signed))
    log_terms = Nx.log(sigmoids + @log_epsilon)
    masked = log_terms * mask
    Nx.sum(masked, axes: [1])
  end

  @doc """
  Returns the hidden activation vector for a list of feature indices.

  ### Arguments

  * `features` is a list of input-matrix row indices, typically from
    `Text.Language.Classifier.Fasttext.Features.extract/2`.

  * `input_matrix` is `model.input_matrix`.

  ### Returns

  * A 1-dimensional `Nx.Tensor` of length `args.dim`. Returns a zero
    vector when the feature list is empty.

  """
  @spec compute_hidden([non_neg_integer()], Nx.Tensor.t()) :: Nx.Tensor.t()
  def compute_hidden([], input_matrix) do
    {_rows, dim} = Nx.shape(input_matrix)
    Nx.broadcast(0.0, {dim}) |> Nx.as_type(Nx.type(input_matrix))
  end

  def compute_hidden(features, input_matrix) when is_list(features) do
    indices = Nx.tensor(features, type: {:s, 64})
    hidden_n(indices, input_matrix)
  end

  @doc """
  Predicts the top-k labels with probabilities for a feature index list.

  ### Arguments

  * `features` is the flat feature index list.

  * `model` is a fully-loaded
    `Text.Language.Classifier.Fasttext.Model`.

  ### Options

  * `:k` — number of top predictions to return. Defaults to `1`.

  * `:threshold` — probability cutoff. Predictions below this are dropped.
    Defaults to `0.0` (matches the fastText Python wrapper default).

  ### Returns

  * A list of `{label, probability}` pairs, sorted descending by
    probability. May be shorter than `k` if `:threshold` excludes
    candidates.

  ### Examples

      iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load("priv/lid_176/lid.176.bin")
      iex> features = Text.Language.Classifier.Fasttext.Features.extract("hello world", model)
      iex> [{label, _prob} | _] = Text.Language.Classifier.Fasttext.Inference.predict_features(features, model, k: 3)
      iex> label
      "en"

  """
  @spec predict_features([non_neg_integer()], Model.t(), keyword()) ::
          [{String.t(), float()}]
  def predict_features(features, %Model{} = model, options \\ []) do
    k = Keyword.get(options, :k, 1)
    threshold = Keyword.get(options, :threshold, 0.0)

    if features == [] do
      []
    else
      indices = Nx.tensor(features, type: {:s, 64})
      score_predictions(indices, model, k, threshold)
    end
  end

  @doc """
  Convenience wrapper: tokenize, extract features, and predict in one step.

  ### Arguments

  * `text` is a UTF-8 binary.

  * `model` is a loaded `Text.Language.Classifier.Fasttext.Model`.

  ### Options

  Same as `predict_features/3`.

  ### Returns

  * `[{label, probability}, ...]`, descending by probability.

  ### Examples

      iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load("priv/lid_176/lid.176.bin")
      iex> [{label, _} | _] = Text.Language.Classifier.Fasttext.Inference.predict("Bonjour le monde", model, k: 3)
      iex> label
      "fr"

  """
  @spec predict(binary(), Model.t(), keyword()) :: [{String.t(), float()}]
  def predict(text, %Model{} = model, options \\ []) when is_binary(text) do
    text
    |> Features.extract(model)
    |> append_eos_feature(model)
    |> predict_features(model, options)
  end

  # The fastText Python wrapper appends a trailing newline to the input
  # before passing it to C++ (see `predict` and `get_sentence_vector` in
  # `python/fasttext_module/fasttext/FastText.py`). The C++ tokenizer
  # turns the trailing `\n` into an EOS token `</s>`. If `</s>` is in
  # vocab — which is the case for `lid.176` — its dictionary index is
  # appended to the feature vector with no character n-grams.
  #
  # Without this step the hidden vector is averaged over one fewer row
  # than the reference, which shifts probabilities by a couple of percent
  # for short inputs.
  defp append_eos_feature(features, %Model{dictionary: dict}) do
    case Map.fetch(dict.word_to_index, @eos_token) do
      {:ok, idx} when idx < dict.nwords -> features ++ [idx]
      _ -> features
    end
  end

  # ---- internal -----------------------------------------------------------

  defp score_predictions(indices, %Model{args: %{loss: :softmax}} = model, k, threshold) do
    probs =
      indices
      |> softmax_probs_n(model.input_matrix, model.output_matrix)
      |> Nx.to_list()

    probs
    |> Enum.with_index()
    |> Enum.flat_map(fn {prob, idx} ->
      if prob >= threshold do
        [{Enum.at(model.labels, idx), prob}]
      else
        []
      end
    end)
    |> Enum.sort_by(fn {_label, prob} -> -prob end)
    |> Enum.take(k)
  end

  defp score_predictions(indices, %Model{args: %{loss: :hs}} = model, k, threshold) do
    %HuffmanTree{vectorised: %{paths: paths, signs: signs, mask: mask}} = model.loss_state

    # Fused vectorised HS scoring: features → hidden → internal_dots →
    # per-leaf log-probabilities, all inside one EXLA graph. Replaces
    # the original recursive BEAM-side DFS that read scalars one at
    # a time and accumulated f32-rounded log/sigmoid by hand.
    log_probs =
      indices
      |> hs_log_probs_n(model.input_matrix, model.output_matrix, paths, signs, mask)
      |> Nx.to_list()

    log_threshold = :math.log(threshold + @log_epsilon)
    labels_tuple = List.to_tuple(model.labels)

    log_probs
    |> Enum.with_index()
    |> Enum.flat_map(fn {score, leaf} ->
      if score >= log_threshold do
        [{elem(labels_tuple, leaf), :math.exp(score)}]
      else
        []
      end
    end)
    |> Enum.sort_by(fn {_label, prob} -> -prob end)
    |> Enum.take(k)
  end

  defp score_predictions(_indices, %Model{args: %{loss: loss}}, _k, _threshold) do
    raise ArgumentError, "inference for loss #{inspect(loss)} is not implemented yet"
  end
end
