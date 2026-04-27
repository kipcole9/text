defmodule Text.Language.Classifier.Fasttext.ModelLoader do
  @moduledoc """
  Parses a fastText `.bin` model file into a
  `Text.Language.Classifier.Fasttext.Model` struct.

  The full byte layout is documented in `docs/lid176_binary_format.md`. In
  brief, the file is a sequence of:

  * 8-byte magic + version header.

  * 56-byte fixed `Args` block.

  * Variable-length `Dictionary` (28-byte header + size entries + optional
    prune index).

  * 1-byte `quant_input` flag (must be `0` — quantized models are out of
    scope for v1).

  * Input matrix (`{nwords + bucket, dim}` float32, row-major).

  * 1-byte `qout` flag (must be `0`).

  * Output matrix (`{nlabels, dim}` float32, row-major).

  The whole file is read into memory and then parsed against an Elixir
  binary. For `lid.176.bin` (~126 MB) this means a transient peak of roughly
  twice the file size during loading: the original binary and the matrix
  tensors live concurrently until the binary becomes garbage collectable.
  Models are normally loaded once at boot, so the peak is acceptable.

  """

  alias Text.Language.Classifier.Fasttext.{Args, Dictionary, HuffmanTree, Model}

  # FASTTEXT_FILEFORMAT_MAGIC_INT32 from src/fasttext.cc
  @magic 793_712_314

  # FASTTEXT_VERSION from src/fasttext.cc
  @max_supported_version 12

  @type load_error ::
          {:bad_magic, integer()}
          | {:unsupported_version, integer()}
          | {:quantized_input_unsupported, true}
          | {:quantized_output_unsupported, true}
          | {:input_matrix_shape_mismatch, %{expected: tuple(), actual: tuple()}}
          | {:output_matrix_shape_mismatch, %{expected: tuple(), actual: tuple()}}
          | :truncated_header
          | :truncated_args
          | :truncated_dictionary_header
          | :truncated_entry
          | :truncated_pruneidx
          | :truncated_quant_flag
          | :truncated_matrix_header
          | :truncated_matrix_data
          | :unterminated_word
          | {:unknown_loss, integer()}
          | {:unknown_model, integer()}
          | File.posix()

  @doc """
  Loads and parses a fastText model file.

  ### Arguments

  * `path` is the absolute or relative path to a fastText `.bin` model file.

  ### Options

  * `:tensor_type` is the `Nx` tensor type used for the input and output
    matrices. The default is `{:f, 32}`, matching fastText's on-disk layout.
    Override only if downstream code requires a different precision.

  ### Returns

  * `{:ok, model}` where `model` is a
    `Text.Language.Classifier.Fasttext.Model` struct.

  * `{:error, reason}` where `reason` describes the parse or validation
    failure. See `t:load_error/0` for the set of possible reasons.

  ### Examples

      # Loading the official lid.176 model (after running mix text.download_model):
      # iex> path = Path.expand("priv/lid_176/lid.176.bin")
      # iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load(path)
      # iex> model.dictionary.nlabels
      # 176

  """
  @spec load(Path.t(), keyword()) :: {:ok, Model.t()} | {:error, load_error()}
  def load(path, options \\ []) do
    tensor_type = Keyword.get(options, :tensor_type, {:f, 32})

    with {:ok, binary} <- File.read(path) do
      decode_model(binary, tensor_type)
    end
  end

  @doc """
  Parses a fastText model from an in-memory binary.

  Useful for testing against synthetic fixtures and for users who already
  have the file contents in memory.

  ### Arguments

  * `binary` is the complete byte sequence of a fastText `.bin` model.

  * `tensor_type` is an `Nx` tensor type. Defaults to `{:f, 32}`.

  ### Returns

  * `{:ok, model}` on success.

  * `{:error, reason}` on parse or validation failure.

  ### Examples

      iex> args = <<
      ...>   8::little-32, 0::little-32, 0::little-32, 0::little-32,
      ...>   0::little-32, 1::little-32, 3::little-32, 3::little-32,
      ...>   4::little-32, 2::little-32, 4::little-32, 0::little-32,
      ...>   1.0e-4::little-float-64
      ...> >>
      iex> dict_header = <<
      ...>   1::little-32, 0::little-32, 1::little-32,
      ...>   0::little-64, 0::little-64
      ...> >>
      iex> entry = "__label__en" <> <<0, 7::little-64, 1::little-8>>
      iex> input_dim = 8
      iex> input_rows = 4
      iex> input_zeros = :binary.copy(<<0::little-float-32>>, input_rows * input_dim)
      iex> input_matrix = <<input_rows::little-64, input_dim::little-64>> <> input_zeros
      iex> output_zeros = :binary.copy(<<0::little-float-32>>, 1 * input_dim)
      iex> output_matrix = <<1::little-64, input_dim::little-64>> <> output_zeros
      iex> binary =
      ...>   <<793_712_314::little-32, 12::little-32>> <>
      ...>     args <> dict_header <> entry <>
      ...>     <<0>> <> input_matrix <>
      ...>     <<0>> <> output_matrix
      iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.decode_model(binary)
      iex> model.labels
      ["en"]

  """
  @spec decode_model(binary(), Nx.Type.t()) :: {:ok, Model.t()} | {:error, load_error()}
  def decode_model(binary, tensor_type \\ {:f, 32}) when is_binary(binary) do
    with {:ok, after_header} <- decode_header(binary),
         {:ok, args, after_args} <- Args.decode(after_header),
         {:ok, dictionary, after_dict} <- Dictionary.decode(after_args),
         {:ok, after_qi_flag} <- decode_input_quant_flag(after_dict),
         {:ok, input_matrix, after_input} <-
           decode_dense_matrix(
             after_qi_flag,
             dictionary.nwords + args.bucket,
             args.dim,
             tensor_type,
             :input_matrix_shape_mismatch
           ),
         {:ok, after_qo_flag} <- decode_output_quant_flag(after_input),
         {:ok, output_matrix, _trailing} <-
           decode_dense_matrix(
             after_qo_flag,
             dictionary.nlabels,
             args.dim,
             tensor_type,
             :output_matrix_shape_mismatch
           ) do
      model = %Model{
        args: args,
        dictionary: dictionary,
        input_matrix: input_matrix,
        output_matrix: output_matrix,
        labels: Dictionary.labels(dictionary),
        loss_state: build_loss_state(args, dictionary)
      }

      {:ok, model}
    end
  end

  defp build_loss_state(%Args{loss: :hs}, dictionary) do
    counts = label_counts(dictionary)
    HuffmanTree.build(counts)
  end

  defp build_loss_state(_args, _dictionary), do: nil

  defp label_counts(dictionary) do
    dictionary.entries
    |> Enum.filter(&(&1.type == :label))
    |> Enum.map(& &1.count)
  end

  defp decode_header(<<@magic::little-signed-32, version::little-signed-32, rest::binary>>) do
    if version > @max_supported_version do
      {:error, {:unsupported_version, version}}
    else
      {:ok, rest}
    end
  end

  defp decode_header(<<bad_magic::little-signed-32, _rest::binary>>) do
    {:error, {:bad_magic, bad_magic}}
  end

  defp decode_header(_truncated), do: {:error, :truncated_header}

  defp decode_input_quant_flag(<<0::little-unsigned-8, rest::binary>>), do: {:ok, rest}

  defp decode_input_quant_flag(<<1::little-unsigned-8, _rest::binary>>),
    do: {:error, {:quantized_input_unsupported, true}}

  defp decode_input_quant_flag(_), do: {:error, :truncated_quant_flag}

  defp decode_output_quant_flag(<<0::little-unsigned-8, rest::binary>>), do: {:ok, rest}

  defp decode_output_quant_flag(<<1::little-unsigned-8, _rest::binary>>),
    do: {:error, {:quantized_output_unsupported, true}}

  defp decode_output_quant_flag(_), do: {:error, :truncated_quant_flag}

  defp decode_dense_matrix(
         <<m::little-signed-64, n::little-signed-64, rest::binary>>,
         expected_m,
         expected_n,
         tensor_type,
         mismatch_tag
       ) do
    cond do
      m != expected_m or n != expected_n ->
        {:error,
         {mismatch_tag, %{expected: {expected_m, expected_n}, actual: {m, n}}}}

      true ->
        byte_count = m * n * 4

        case rest do
          <<data::binary-size(^byte_count), trailing::binary>> ->
            tensor =
              data
              |> Nx.from_binary({:f, 32})
              |> Nx.reshape({m, n})
              |> maybe_convert_type(tensor_type)

            {:ok, tensor, trailing}

          _ ->
            {:error, :truncated_matrix_data}
        end
    end
  end

  defp decode_dense_matrix(_truncated, _m, _n, _type, _tag),
    do: {:error, :truncated_matrix_header}

  defp maybe_convert_type(tensor, {:f, 32}), do: tensor
  defp maybe_convert_type(tensor, type), do: Nx.as_type(tensor, type)
end
