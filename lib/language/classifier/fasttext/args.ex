defmodule Text.Language.Classifier.Fasttext.Args do
  @moduledoc """
  Training and model hyperparameters extracted from a fastText model file.

  Mirrors the C++ `fasttext::Args` struct as written by `Args::save`. See
  `docs/lid176_binary_format.md` (Section 2) for the exact byte layout.

  Most fields are training-time hyperparameters that do not affect inference
  but are preserved for completeness. The fields that matter at inference time
  for a `lid.176`-style supervised model are `dim`, `bucket`, `minn`, and
  `maxn`.

  """

  @loss_names %{1 => :hs, 2 => :ns, 3 => :softmax, 4 => :ova}
  @model_names %{1 => :cbow, 2 => :sg, 3 => :sup}

  @type loss :: :hs | :ns | :softmax | :ova
  @type model :: :cbow | :sg | :sup

  @type t :: %__MODULE__{
          dim: non_neg_integer(),
          ws: non_neg_integer(),
          epoch: non_neg_integer(),
          min_count: non_neg_integer(),
          neg: non_neg_integer(),
          word_ngrams: non_neg_integer(),
          loss: loss(),
          model: model(),
          bucket: non_neg_integer(),
          minn: non_neg_integer(),
          maxn: non_neg_integer(),
          lr_update_rate: non_neg_integer(),
          t: float()
        }

  defstruct [
    :dim,
    :ws,
    :epoch,
    :min_count,
    :neg,
    :word_ngrams,
    :loss,
    :model,
    :bucket,
    :minn,
    :maxn,
    :lr_update_rate,
    :t
  ]

  @doc """
  Decodes the 56-byte `Args` block that follows the magic + version header.

  ### Arguments

  * `binary` is the raw byte sequence positioned at the start of the args
    block. Must contain at least 56 bytes.

  ### Returns

  * `{:ok, args, rest}` where `args` is a `t:t/0` struct and `rest` is the
    binary remainder positioned at the start of the dictionary block.

  * `{:error, reason}` if the binary is truncated or contains an unknown
    `loss`/`model` enum value.

  ### Examples

      iex> args_bytes = <<
      ...>   16::little-32, 5::little-32, 1::little-32, 1000::little-32,
      ...>   5::little-32, 1::little-32, 3::little-32, 3::little-32,
      ...>   2_000_000::little-32, 2::little-32, 4::little-32, 100::little-32,
      ...>   1.0e-4::little-float-64
      ...> >>
      iex> {:ok, args, rest} = Text.Language.Classifier.Fasttext.Args.decode(args_bytes)
      iex> {args.dim, args.bucket, args.loss, args.model, rest}
      {16, 2_000_000, :softmax, :sup, ""}

  """
  @spec decode(binary()) ::
          {:ok, t(), binary()} | {:error, term()}
  def decode(<<
        dim::little-signed-32,
        ws::little-signed-32,
        epoch::little-signed-32,
        min_count::little-signed-32,
        neg::little-signed-32,
        word_ngrams::little-signed-32,
        loss::little-signed-32,
        model::little-signed-32,
        bucket::little-signed-32,
        minn::little-signed-32,
        maxn::little-signed-32,
        lr_update_rate::little-signed-32,
        t::little-float-64,
        rest::binary
      >>) do
    with {:ok, loss_name} <- decode_loss(loss),
         {:ok, model_name} <- decode_model(model) do
      args = %__MODULE__{
        dim: dim,
        ws: ws,
        epoch: epoch,
        min_count: min_count,
        neg: neg,
        word_ngrams: word_ngrams,
        loss: loss_name,
        model: model_name,
        bucket: bucket,
        minn: minn,
        maxn: maxn,
        lr_update_rate: lr_update_rate,
        t: t
      }

      {:ok, args, rest}
    end
  end

  def decode(_truncated), do: {:error, :truncated_args}

  defp decode_loss(value) do
    case Map.fetch(@loss_names, value) do
      {:ok, name} -> {:ok, name}
      :error -> {:error, {:unknown_loss, value}}
    end
  end

  defp decode_model(value) do
    case Map.fetch(@model_names, value) do
      {:ok, name} -> {:ok, name}
      :error -> {:error, {:unknown_model, value}}
    end
  end
end
