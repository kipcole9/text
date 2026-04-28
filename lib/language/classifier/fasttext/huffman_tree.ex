defmodule Text.Language.Classifier.Fasttext.HuffmanTree do
  @moduledoc """
  The Huffman tree fastText constructs over output labels for hierarchical
  softmax inference.

  fastText uses hierarchical softmax (`loss = :hs`) when training models
  like `lid.176`. At inference the output projection is *not* a single
  matrix multiplication: instead a binary tree is traversed root-to-leaf,
  with each internal node carrying a learned vector that scores a
  left-vs-right decision. This module reproduces fastText's tree
  construction so the Elixir inference path can follow the same paths the
  C++ does.

  Mirrors `HierarchicalSoftmaxLoss::buildTree` in `src/loss.cc`.

  ### Tree shape

  Given `n` labels:

  * Total nodes: `2n - 1` (numbered `0..2n-2`).
  * Leaves: `0..n-1`. Leaf `i` corresponds to label `i`. The label index
    matches the dictionary's label entry order (after fastText's count-desc
    sort).
  * Internal nodes: `n..2n-2`. Each internal node `m` has a learned vector
    stored in row `m - n` of the output matrix.
  * Root: `2n - 2`.

  ### Build algorithm

  Labels are assumed sorted by count *descending* (fastText's
  `Dictionary::threshold` enforces this). Two pointers walk inward — `leaf`
  decrements from `n-1` (smallest leaf counts first), `node` increments
  from `n` (newly-formed internal nodes, count = sum of children, naturally
  monotone). Each internal slot consumes the two smallest available counts.

  The right child of every internal node is flagged as `binary=true`,
  meaning a score path that goes right uses `log(sigmoid(score))` while
  the left child uses `log(1 - sigmoid(score))`. This matches the
  reference's `tree_[mini[1]].binary = true` line.

  """

  @type node_index :: non_neg_integer()

  @type tree_node :: %{
          parent: integer(),
          left: integer(),
          right: integer(),
          count: non_neg_integer(),
          binary: boolean()
        }

  @typedoc """
  Vectorised representation of every leaf's path through the tree.

  All three tensors are shape `{nlabels, max_depth}`:

  * `paths` — `int32`. `paths[i, j]` is the *output-matrix row index*
    for the j-th internal node on leaf i's path (i.e. `node_id - osz`).
    Padding positions are `0`; the corresponding `mask` entry is also
    `0` so the contribution is ignored. The choice of `0` for padding
    is safe because `Nx.take` always returns a defined value.

  * `signs` — `f32`. `+1.0` if the leaf branches *right* at this
    node (uses `log(sigmoid(dot))`), `-1.0` if it branches *left*
    (uses `log(1 - sigmoid(dot)) = log(sigmoid(-dot))`). Padding
    positions are `+1.0`.

  * `mask` — `f32`, `1.0` for valid path positions and `0.0` for
    padding. Multiplied into per-step log-probabilities to zero-out
    padding contributions.

  Materialised once at `build/1` time. Used by
  `Text.Language.Classifier.Fasttext.Inference` to score all leaves in
  a single fused EXLA kernel (one `take + multiply + sigmoid + log
  + sum`) instead of the original recursive BEAM-side DFS.
  """
  @type vectorised_paths :: %{
          paths: Nx.Tensor.t(),
          signs: Nx.Tensor.t(),
          mask: Nx.Tensor.t(),
          max_depth: non_neg_integer()
        }

  @type t :: %__MODULE__{
          osz: pos_integer(),
          # Erlang `:array` indexed 0..2*osz-2.
          nodes: :array.array(tree_node()),
          # Pre-computed per-leaf path matrices for vectorised scoring.
          vectorised: vectorised_paths()
        }

  defstruct [:osz, :nodes, :vectorised]

  @doc """
  Builds a Huffman tree from a list of label counts.

  ### Arguments

  * `counts` is a non-empty list of non-negative integers, in label order.
    For fastText models loaded by `ModelLoader.load/2`, the order matches
    the dictionary's label-typed entries (already count-descending).

  ### Returns

  * A `t:t/0` struct with all internal nodes populated.

  ### Examples

      iex> tree = Text.Language.Classifier.Fasttext.HuffmanTree.build([5, 3, 1])
      iex> tree.osz
      3
      iex> # 3 leaves + 2 internal = 5 nodes total
      iex> :array.size(tree.nodes)
      5
      iex> root = Text.Language.Classifier.Fasttext.HuffmanTree.root(tree)
      iex> root
      4

  """
  @spec build([non_neg_integer()]) :: t()
  def build(counts) when is_list(counts) and counts != [] do
    osz = length(counts)
    total = 2 * osz - 1

    initial =
      :array.new(
        size: total,
        default: %{
          parent: -1,
          left: -1,
          right: -1,
          count: 1_000_000_000_000_000,
          binary: false
        }
      )

    nodes =
      counts
      |> Enum.with_index()
      |> Enum.reduce(initial, fn {count, i}, acc ->
        :array.set(
          i,
          %{parent: -1, left: -1, right: -1, count: count, binary: false},
          acc
        )
      end)

    nodes = build_internals(nodes, osz, osz - 1, osz, osz)
    vectorised = vectorise_paths(nodes, osz)

    %__MODULE__{osz: osz, nodes: nodes, vectorised: vectorised}
  end

  # ---- vectorised path materialisation -----------------------------------

  # Walk each leaf to the root collecting (output_row_index, sign)
  # pairs. Output_row_index is `node_id - osz` so the same indices
  # work directly against the precomputed `internal_dots` vector in
  # `Inference`. Sign is `+1.0` for right-child branches (the classic
  # `binary == true` flag), `-1.0` for left-child branches.
  defp vectorise_paths(nodes, osz) do
    leaf_paths =
      for leaf_id <- 0..(osz - 1) do
        collect_path_to_root(nodes, leaf_id, osz, [])
      end

    max_depth =
      leaf_paths
      |> Enum.map(&length/1)
      |> Enum.max(fn -> 0 end)

    paths =
      leaf_paths
      |> Enum.map(fn path -> pad_path(path, max_depth) end)

    paths_tensor =
      paths
      |> Enum.map(fn entries -> Enum.map(entries, fn {row, _sign, _valid} -> row end) end)
      |> Nx.tensor(type: {:s, 32})

    signs_tensor =
      paths
      |> Enum.map(fn entries -> Enum.map(entries, fn {_row, sign, _valid} -> sign end) end)
      |> Nx.tensor(type: {:f, 32})

    mask_tensor =
      paths
      |> Enum.map(fn entries -> Enum.map(entries, fn {_row, _sign, valid} -> valid end) end)
      |> Nx.tensor(type: {:f, 32})

    %{paths: paths_tensor, signs: signs_tensor, mask: mask_tensor, max_depth: max_depth}
  end

  defp collect_path_to_root(nodes, node_id, osz, acc) do
    case :array.get(node_id, nodes) do
      %{parent: -1} ->
        Enum.reverse(acc)

      %{parent: parent_id} ->
        parent = :array.get(parent_id, nodes)

        sign =
          cond do
            parent.right == node_id -> 1.0
            parent.left == node_id -> -1.0
            true -> 0.0
          end

        # parent_id is an internal node; its index into the output
        # matrix is parent_id - osz.
        entry = {parent_id - osz, sign, 1.0}
        collect_path_to_root(nodes, parent_id, osz, [entry | acc])
    end
  end

  # Pad with `{0, 1.0, 0.0}`: row index 0 is a valid (and probably
  # populated) row, sign is +1, but mask is 0 so the contribution is
  # multiplied out. Using row 0 means `Nx.take` always returns a real
  # value and we don't have to special-case sentinels in the defn.
  defp pad_path(entries, max_depth) do
    pad = max_depth - length(entries)
    entries ++ List.duplicate({0, 1.0, 0.0}, pad)
  end

  defp build_internals(nodes, osz, _leaf, _node, i) when i >= 2 * osz - 1, do: nodes

  defp build_internals(nodes, osz, leaf, node, i) do
    {first, leaf, node} = pick_smaller(nodes, leaf, node)
    {second, leaf, node} = pick_smaller(nodes, leaf, node)

    first_count = :array.get(first, nodes).count
    second_count = :array.get(second, nodes).count

    new_internal = %{
      parent: -1,
      left: first,
      right: second,
      count: first_count + second_count,
      binary: false
    }

    nodes = :array.set(i, new_internal, nodes)
    nodes = update_node(nodes, first, fn entry -> %{entry | parent: i} end)
    nodes = update_node(nodes, second, fn entry -> %{entry | parent: i, binary: true} end)

    build_internals(nodes, osz, leaf, node, i + 1)
  end

  defp pick_smaller(nodes, leaf, node) do
    leaf_count = if leaf >= 0, do: :array.get(leaf, nodes).count, else: nil
    node_count = :array.get(node, nodes).count

    if leaf >= 0 and leaf_count < node_count do
      {leaf, leaf - 1, node}
    else
      {node, leaf, node + 1}
    end
  end

  defp update_node(nodes, idx, f) do
    :array.set(idx, f.(:array.get(idx, nodes)), nodes)
  end

  @doc """
  Returns the root index (always `2 * osz - 2`).
  """
  @spec root(t()) :: node_index()
  def root(%__MODULE__{osz: osz}), do: 2 * osz - 2

  @doc """
  Returns the node at `index`.
  """
  @spec node_at(t(), node_index()) :: tree_node()
  def node_at(%__MODULE__{nodes: nodes}, index), do: :array.get(index, nodes)

  @doc """
  Returns whether the node at `index` is a leaf.
  """
  @spec leaf?(t(), node_index()) :: boolean()
  def leaf?(%__MODULE__{} = tree, index) do
    n = node_at(tree, index)
    n.left == -1 and n.right == -1
  end
end
