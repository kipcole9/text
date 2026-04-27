defmodule Text.Language.Classifier.Fasttext.Dictionary do
  @moduledoc """
  Vocabulary and label table parsed from a fastText model file.

  Mirrors the C++ `fasttext::Dictionary` data written by `Dictionary::save`.
  Each entry is a `Text.Language.Classifier.Fasttext.Entry` carrying the
  surface form (UTF-8 string), occurrence count from training, and a
  word/label tag.

  Entries are stored in two collections:

  * `entries` is the original sequence in file order. Index `i` here is the
    same `i` used elsewhere in fastText to address the input matrix for word
    rows.

  * `word_to_index` is a precomputed lookup keyed by the surface form,
    mapping back to the entry index. Built once at load time so feature
    extraction can do O(1) lookups.

  See `docs/lid176_binary_format.md` (Section 3) for the byte layout.

  """

  alias Text.Language.Classifier.Fasttext.Entry

  @type t :: %__MODULE__{
          size: non_neg_integer(),
          nwords: non_neg_integer(),
          nlabels: non_neg_integer(),
          ntokens: non_neg_integer(),
          pruneidx_size: non_neg_integer(),
          entries: [Entry.t()],
          word_to_index: %{String.t() => non_neg_integer()},
          pruneidx: %{integer() => integer()}
        }

  defstruct [
    :size,
    :nwords,
    :nlabels,
    :ntokens,
    :pruneidx_size,
    :entries,
    :word_to_index,
    :pruneidx
  ]

  @label_prefix "__label__"

  @doc """
  Decodes the dictionary section of a fastText model file.

  ### Arguments

  * `binary` is the raw byte sequence positioned at the start of the
    dictionary block (immediately after the args block).

  ### Returns

  * `{:ok, dictionary, rest}` where `dictionary` is a `t:t/0` struct and
    `rest` is the binary remainder positioned at the start of the
    `quant_input` flag byte.

  * `{:error, reason}` if the input is truncated or malformed (e.g. an
    unterminated word string, an out-of-range entry type byte).

  """
  @spec decode(binary()) :: {:ok, t(), binary()} | {:error, term()}
  def decode(<<
        size::little-signed-32,
        nwords::little-signed-32,
        nlabels::little-signed-32,
        ntokens::little-signed-64,
        pruneidx_size::little-signed-64,
        rest::binary
      >>)
      when size >= 0 and nwords >= 0 and nlabels >= 0 do
    # `pruneidx_size` is `-1` for unpruned models (matches the C++
    # `Dictionary` constructor default; newer fastText versions persist this
    # sentinel rather than `0`). `0` means "model went through pruning but
    # produced no entries" — rare but legal. `> 0` is a populated prune
    # index. Only the positive case has any pairs to read from the file.
    pruneidx_to_read = max(pruneidx_size, 0)

    with {:ok, entries, rest} <- decode_entries(rest, size, []),
         {:ok, pruneidx, rest} <- decode_pruneidx(rest, pruneidx_to_read, %{}) do
      word_to_index =
        entries
        |> Enum.with_index()
        |> Map.new(fn {%Entry{word: word}, index} -> {word, index} end)

      dict = %__MODULE__{
        size: size,
        nwords: nwords,
        nlabels: nlabels,
        ntokens: ntokens,
        pruneidx_size: pruneidx_size,
        entries: entries,
        word_to_index: word_to_index,
        pruneidx: pruneidx
      }

      {:ok, dict, rest}
    end
  end

  def decode(_truncated), do: {:error, :truncated_dictionary_header}

  @doc """
  Returns the labels (in file order) with the `__label__` prefix stripped.

  For `lid.176` this produces a 176-element list of language tags such as
  `["en", "zh-Hans", "fr", ...]`. Index `i` in the returned list corresponds
  to row `i` of the output matrix.

  ### Arguments

  * `dictionary` is a parsed `t:t/0`.

  ### Returns

  * A list of `nlabels` strings.

  """
  @spec labels(t()) :: [String.t()]
  def labels(%__MODULE__{entries: entries}) do
    entries
    |> Enum.filter(&(&1.type == :label))
    |> Enum.map(&strip_label_prefix(&1.word))
  end

  defp strip_label_prefix(@label_prefix <> rest), do: rest
  defp strip_label_prefix(other), do: other

  defp decode_entries(rest, 0, acc), do: {:ok, Enum.reverse(acc), rest}

  defp decode_entries(binary, remaining, acc) when remaining > 0 do
    with {:ok, word, after_word} <- read_null_terminated(binary),
         <<count::little-signed-64, type::little-signed-8, rest::binary>> <- after_word do
      entry = %Entry{word: word, count: count, type: Entry.type_from_int8(type)}
      decode_entries(rest, remaining - 1, [entry | acc])
    else
      {:error, _} = error -> error
      _ -> {:error, :truncated_entry}
    end
  end

  defp decode_pruneidx(rest, 0, acc), do: {:ok, acc, rest}

  defp decode_pruneidx(
         <<first::little-signed-32, second::little-signed-32, rest::binary>>,
         remaining,
         acc
       )
       when remaining > 0 do
    decode_pruneidx(rest, remaining - 1, Map.put(acc, first, second))
  end

  defp decode_pruneidx(_truncated, _remaining, _acc), do: {:error, :truncated_pruneidx}

  defp read_null_terminated(binary) do
    case :binary.match(binary, <<0>>) do
      {pos, 1} ->
        <<word::binary-size(^pos), 0, rest::binary>> = binary
        {:ok, word, rest}

      :nomatch ->
        {:error, :unterminated_word}
    end
  end
end
