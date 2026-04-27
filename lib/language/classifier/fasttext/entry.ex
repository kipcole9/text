defmodule Text.Language.Classifier.Fasttext.Entry do
  @moduledoc """
  A single dictionary entry parsed from a fastText model file.

  An entry is either a vocabulary word (`type: :word`) or a label
  (`type: :label`). For `lid.176`, label entries hold strings like
  `"__label__en"`, `"__label__zh-Hans"`, etc.

  See `docs/lid176_binary_format.md` (Section 3) for the byte layout.

  """

  @type entry_type :: :word | :label

  @type t :: %__MODULE__{
          word: String.t(),
          count: non_neg_integer(),
          type: entry_type()
        }

  defstruct [:word, :count, :type]

  @doc false
  @spec type_from_int8(0 | 1) :: entry_type()
  def type_from_int8(0), do: :word
  def type_from_int8(1), do: :label
end
