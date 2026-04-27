defmodule Text.Language.Classifier.Fasttext.Model do
  @moduledoc """
  A fully-loaded fastText model.

  Holds the parsed args and dictionary plus the input and output matrices as
  `Nx` tensors. The input matrix is the largest piece of memory in the
  struct: for `lid.176.bin` it is a `{nwords + bucket, dim}` tensor of
  float32 values, approximately 128 MB.

  Models are produced by `Text.Language.Classifier.Fasttext.ModelLoader.load/2`
  from a fastText `.bin` file.

  ### Fields

  * `args` is the parsed `Text.Language.Classifier.Fasttext.Args` struct.

  * `dictionary` is the parsed
    `Text.Language.Classifier.Fasttext.Dictionary` struct.

  * `input_matrix` is an `Nx` tensor of shape `{args.bucket + dictionary.nwords, args.dim}`
    holding the row-major input embeddings (word rows first, then subword
    n-gram rows).

  * `output_matrix` is an `Nx` tensor of shape
    `{dictionary.nlabels, args.dim}` holding the per-label output vectors.

  * `labels` is the list of language label strings (with the `__label__`
    prefix stripped) in row order matching `output_matrix`. For `lid.176`
    this is a 176-element list such as `["en", "zh-Hans", ...]`.

  """

  alias Text.Language.Classifier.Fasttext.{Args, Dictionary, HuffmanTree}

  @typedoc """
  Loss-specific decoding state, built once at load time and reused for every
  prediction.

  * For `:hs` (hierarchical softmax) the state is a
    `Text.Language.Classifier.Fasttext.HuffmanTree` constructed from the
    label counts.

  * For `:softmax` no extra state is needed; the field is `nil`.

  * `:ns` and `:ova` are not yet supported by the inference path.
  """
  @type loss_state :: HuffmanTree.t() | nil

  @type t :: %__MODULE__{
          args: Args.t(),
          dictionary: Dictionary.t(),
          input_matrix: Nx.Tensor.t(),
          output_matrix: Nx.Tensor.t(),
          labels: [String.t()],
          loss_state: loss_state()
        }

  defstruct [:args, :dictionary, :input_matrix, :output_matrix, :labels, :loss_state]
end
