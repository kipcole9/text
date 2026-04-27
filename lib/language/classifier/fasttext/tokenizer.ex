defmodule Text.Language.Classifier.Fasttext.Tokenizer do
  @moduledoc """
  Whitespace tokenizer matching fastText's `Dictionary::readWord`.

  fastText splits on a fixed byte set: space, newline, carriage return,
  tab, vertical tab, form feed, and NUL. Any maximal run of non-whitespace
  bytes between whitespace bytes (or string boundaries) is one token. The
  rules are byte-level, not codepoint-level, so this implementation is not
  Unicode-aware — that intentionally mirrors the reference.

  At inference time the official Python wrapper replaces newlines with
  spaces before calling into C++ (`predict` in `python/fasttext_module/fasttext/FastText.py`).
  This tokenizer takes the same approach: callers wanting strict Python
  parity can pre-strip newlines themselves, but the default behaviour
  treats `\\n` as whitespace and never emits the special `</s>` EOS token
  that the training-time `readWord` would produce.

  See `src/dictionary.cc` (`Dictionary::readWord`,
  `Dictionary::readWordNoNewline`).

  """

  # The exact whitespace set fastText uses.
  @whitespace_chars [?\s, ?\n, ?\r, ?\t, ?\v, ?\f, 0]

  @doc """
  Splits a binary into tokens using fastText's whitespace rules.

  ### Arguments

  * `text` is a UTF-8 binary or arbitrary byte sequence. Whitespace is
    treated at the byte level: a stray byte in `[\\s, \\n, \\r, \\t, \\v,
    \\f, \\0]` is a separator no matter what surrounding bytes look like.

  ### Returns

  * A list of binaries, in document order, with no empty tokens. Returns
    `[]` for empty or whitespace-only input.

  ### Examples

      iex> Text.Language.Classifier.Fasttext.Tokenizer.tokenize("hello world")
      ["hello", "world"]

      iex> Text.Language.Classifier.Fasttext.Tokenizer.tokenize("  hello\\tworld\\n")
      ["hello", "world"]

      iex> Text.Language.Classifier.Fasttext.Tokenizer.tokenize("")
      []

      iex> Text.Language.Classifier.Fasttext.Tokenizer.tokenize("一個 中文 句子")
      ["一個", "中文", "句子"]

  """
  @spec tokenize(binary()) :: [binary()]
  def tokenize(text) when is_binary(text) do
    do_tokenize(text, 0, 0, byte_size(text), [])
  end

  # Walk the binary one byte at a time, collecting non-whitespace runs.
  # `start` is the byte offset of the current candidate token; `pos` is
  # the byte offset under inspection.
  defp do_tokenize(text, start, pos, size, acc) when pos >= size do
    acc =
      if pos > start do
        [:binary.part(text, start, pos - start) | acc]
      else
        acc
      end

    Enum.reverse(acc)
  end

  defp do_tokenize(text, start, pos, size, acc) do
    if whitespace?(:binary.at(text, pos)) do
      acc =
        if pos > start do
          [:binary.part(text, start, pos - start) | acc]
        else
          acc
        end

      do_tokenize(text, pos + 1, pos + 1, size, acc)
    else
      do_tokenize(text, start, pos + 1, size, acc)
    end
  end

  @compile {:inline, whitespace?: 1}
  defp whitespace?(byte), do: byte in @whitespace_chars
end
