defmodule Text.Language.Classifier.Fasttext.Hash do
  @moduledoc """
  Bit-exact port of fastText's string hash function.

  fastText uses a Fowler–Noll–Vo (FNV-1a) variant with one quirk: each input
  byte is reinterpreted as a signed 8-bit integer before being widened to
  unsigned 32-bit. Bytes with the high bit set therefore contribute their
  sign-extended value to the hash mix step, not their unsigned value. This
  is documented in `src/dictionary.cc` (`Dictionary::hash`) of the fastText
  source as a deliberate compatibility decision so that all already-released
  models hash identically.

  Translating the C++ literally:

      uint32_t h = 2166136261;
      for (size_t i = 0; i < str.size(); i++) {
        h = h ^ uint32_t(int8_t(str[i]));
        h = h * 16777619;
      }

  The two constants are the canonical FNV offset basis and FNV prime for
  32-bit FNV-1a.

  Any deviation from the reference here will silently produce wrong subword
  indices and wreck the model's predictions for non-ASCII scripts. The hash
  is exercised by golden tests against fastText's own `get_subwords/1`
  output for a large corpus of words.

  """

  import Bitwise

  @offset_basis 2_166_136_261
  @prime 16_777_619
  @uint32_mask 0xFFFFFFFF

  @doc """
  Returns the 32-bit FNV-1a-with-signed-byte hash of a binary.

  ### Arguments

  * `binary` is any UTF-8 string or arbitrary byte sequence. fastText
    operates on UTF-8 byte sequences, so passing a `t:String.t/0` is the
    typical use.

  ### Returns

  * A non-negative integer in `[0, 2^32 - 1]`.

  ### Examples

      iex> Text.Language.Classifier.Fasttext.Hash.hash("")
      2166136261

      iex> Text.Language.Classifier.Fasttext.Hash.hash("a")
      3826002220

      iex> Text.Language.Classifier.Fasttext.Hash.hash("the")
      3020861980

  """
  @spec hash(binary()) :: non_neg_integer()
  def hash(binary) when is_binary(binary) do
    do_hash(binary, @offset_basis)
  end

  defp do_hash(<<>>, h), do: h

  defp do_hash(<<byte, rest::binary>>, h) do
    sign_extended = sign_extend(byte)
    xored = bxor(h, sign_extended)
    mixed = band(xored * @prime, @uint32_mask)
    do_hash(rest, mixed)
  end

  # Reinterprets a 0..255 byte as `int8` cast to `uint32`. Bytes with the
  # high bit set become 0xFFFFFF80..0xFFFFFFFF after sign extension.
  @compile {:inline, sign_extend: 1}
  defp sign_extend(byte) when byte < 128, do: byte
  defp sign_extend(byte), do: @uint32_mask - 256 + byte + 1
end
