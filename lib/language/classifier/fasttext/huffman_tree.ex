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

  @type t :: %__MODULE__{
          osz: pos_integer(),
          # Erlang `:array` indexed 0..2*osz-2.
          nodes: :array.array(tree_node())
        }

  defstruct [:osz, :nodes]

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
      :array.new(size: total, default: %{
        parent: -1,
        left: -1,
        right: -1,
        count: 1_000_000_000_000_000,
        binary: false
      })

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

    %__MODULE__{osz: osz, nodes: nodes}
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
