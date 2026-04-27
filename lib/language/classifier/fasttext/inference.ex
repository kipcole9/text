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

  alias Text.Language.Classifier.Fasttext.{Features, HuffmanTree, Model}

  @log_epsilon 1.0e-5
  @eos_token "</s>"

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

    input_matrix
    |> Nx.take(indices, axis: 0)
    |> Nx.mean(axes: [0])
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
      hidden = compute_hidden(features, model.input_matrix)
      score_predictions(hidden, model, k, threshold)
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

  defp score_predictions(hidden, %Model{args: %{loss: :softmax}} = model, k, threshold) do
    probs =
      model.output_matrix
      |> Nx.dot(hidden)
      |> softmax()
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

  defp score_predictions(hidden, %Model{args: %{loss: :hs}} = model, k, threshold) do
    %HuffmanTree{} = tree = model.loss_state

    # Compute all internal-node dot products in one Nx call. This keeps the
    # arithmetic in the same f32 precision the C++ reference uses; the
    # earlier per-node loop in pure Elixir promoted to f64 and produced
    # tail-label mismatches when nearby probabilities were within rounding.
    internal_dots =
      model.output_matrix
      |> Nx.dot(Nx.as_type(hidden, {:f, 32}))
      |> Nx.to_list()
      |> List.to_tuple()

    labels_tuple = List.to_tuple(model.labels)

    candidates =
      hs_dfs(
        tree,
        HuffmanTree.root(tree),
        0.0,
        internal_dots,
        k,
        :math.log(threshold + @log_epsilon),
        []
      )

    candidates
    |> Enum.sort_by(fn {score, _idx} -> -score end)
    |> Enum.take(k)
    |> Enum.map(fn {score, leaf} -> {elem(labels_tuple, leaf), :math.exp(score)} end)
  end

  defp score_predictions(_hidden, %Model{args: %{loss: loss}}, _k, _threshold) do
    raise ArgumentError, "inference for loss #{inspect(loss)} is not implemented yet"
  end

  # Stable softmax: subtract max before exponentiating.
  defp softmax(tensor) do
    shifted = Nx.subtract(tensor, Nx.reduce_max(tensor))
    exps = Nx.exp(shifted)
    Nx.divide(exps, Nx.sum(exps))
  end

  # ---- hierarchical-softmax DFS -------------------------------------------

  # Returns a list of `{score, leaf_index}` candidates with at most k
  # entries, pruned by score and threshold.
  defp hs_dfs(tree, node_idx, score, internal_dots, k, log_threshold, acc) do
    cond do
      score < log_threshold ->
        acc

      length(acc) >= k and score < min_score(acc) ->
        acc

      true ->
        node = HuffmanTree.node_at(tree, node_idx)

        if node.left == -1 and node.right == -1 do
          insert_candidate(acc, {score, node_idx}, k)
        else
          # The C++ reference performs every arithmetic step in float32
          # (each `real` is `float`; intermediate doubles are narrowed
          # back). Erlang has only float64, so we round to f32 at every
          # step the C++ code would. Without this, log/exp accumulation
          # over the ~7-deep tree drifts by ~1-2% from the reference.
          dot = elem(internal_dots, node_idx - tree.osz)
          f = f32(sigmoid(dot))
          left_score = f32(score + f32(log_with_eps(f32(1.0 - f))))
          right_score = f32(score + f32(log_with_eps(f)))

          acc = hs_dfs(tree, node.left, left_score, internal_dots, k, log_threshold, acc)
          hs_dfs(tree, node.right, right_score, internal_dots, k, log_threshold, acc)
        end
    end
  end

  defp sigmoid(x), do: 1.0 / (1.0 + :math.exp(-x))

  defp log_with_eps(x), do: :math.log(x + @log_epsilon)

  # Narrows an Erlang float (f64) to the value it would have as IEEE-754
  # binary32 (single precision), returned back as an f64. Used to mimic
  # the C++ reference's per-step f32 rounding without leaving the BEAM's
  # native float type.
  defp f32(x) do
    <<rounded::float-32>> = <<x::float-32>>
    rounded
  end

  defp insert_candidate(acc, {_score, _leaf} = entry, k) do
    cond do
      length(acc) < k -> [entry | acc]
      true -> [entry | acc] |> Enum.sort_by(fn {s, _} -> -s end) |> Enum.take(k)
    end
  end

  defp min_score(acc) do
    acc
    |> Enum.map(fn {s, _} -> s end)
    |> Enum.min()
  end
end
