defmodule Text.Language.Classifier.Fasttext.Features do
  @moduledoc """
  Converts an input string into the flat list of input-matrix row indices
  that fastText averages to produce a feature vector.

  Mirrors `Dictionary::getStringNoNewline` / `Dictionary::addSubwords` /
  `Dictionary::addWordNgrams` from the C++ reference (`src/dictionary.cc`),
  specialized for the inference path used by the Python `predict` wrapper:

  * Newlines are pre-replaced with spaces by the caller, so EOS tokens are
    not produced.

  * `wordNgrams = 1` (the `lid.176` setting) collapses
    `addWordNgrams` to a no-op, so word-level n-gram hashes are never
    pushed.

  * Label-typed tokens — either a known label entry in the dictionary, or
    an unknown token that starts with the `__label__` prefix — are
    excluded from the word-feature list. They would have been routed to
    the `labels` vector in the C++ code, which is unused at inference.

  The returned list is the exact sequence of row indices that the C++
  averages to compute the input feature vector. Phase 5 turns it into an
  `Nx.take` and a mean.

  ### What ends up in the list, per token

  | Token state                                  | Contribution                                       |
  |----------------------------------------------|----------------------------------------------------|
  | In-vocab word entry                          | `[wid]` followed by character-n-gram subword indices |
  | Out-of-vocab, no `__label__` prefix          | character-n-gram subword indices only              |
  | In-vocab label entry                         | dropped                                            |
  | Out-of-vocab, starts with `__label__` prefix | dropped                                            |

  Subword indices are produced by
  `Text.Language.Classifier.Fasttext.Subwords.compute_indices/3`, which
  honours the model's `pruneidx` regime.

  """

  alias Text.Language.Classifier.Fasttext.{Model, Subwords, Tokenizer}

  # fastText's default label prefix. Captured in `Args` as a training-time
  # setting; for `lid.176` (and every other public model) this is the
  # value used.
  @label_prefix "__label__"

  # fastText's end-of-sentence sentinel. Stored in the dictionary as a
  # word-typed entry with `subwords = [eos_idx]` (special-cased in
  # `Dictionary::initNgrams` — EOS does NOT get character n-grams).
  @eos_token "</s>"

  @doc """
  Returns the input-matrix row indices for the features of `text`.

  ### Arguments

  * `text` is a UTF-8 binary. Newlines are treated as whitespace
    separators (matching the Python `predict` wrapper, which strips them
    before tokenizing).

  * `model` is a fully-loaded
    `Text.Language.Classifier.Fasttext.Model`.

  ### Returns

  * A list of non-negative integers, each a valid row index into
    `model.input_matrix`. The list may be empty if the input contains no
    word-typed tokens.

  ### Examples

  Given a loaded `lid.176` model, `extract/2` returns the same row index
  list the C++ reference would average:

      # iex> {:ok, model} = Text.Language.Classifier.Fasttext.ModelLoader.load("priv/lid_176/lid.176.bin")
      # iex> Text.Language.Classifier.Fasttext.Features.extract("hello world", model)
      # [..., ...]  # word and subword indices for both tokens

  Label-shaped tokens are dropped:

      # iex> Text.Language.Classifier.Fasttext.Features.extract("__label__en hello", model)
      # [...]  # only the features for "hello"

  """
  @spec extract(binary(), Model.t()) :: [non_neg_integer()]
  def extract(text, %Model{} = model) when is_binary(text) do
    text
    |> Tokenizer.tokenize()
    |> Enum.flat_map(&token_features(&1, model))
  end

  defp token_features(token, model) do
    %Model{args: args, dictionary: dict} = model

    case Map.fetch(dict.word_to_index, token) do
      {:ok, idx} when idx < dict.nwords ->
        # In-vocab word: emit the word's own row, then its subword rows.
        # The reference precomputes these once at load time as
        # `[i] ++ computeSubwords(BOW + word + EOW)`; recomputing them on
        # demand here is identical because the inputs are identical.
        # Exception: the EOS token is special-cased by `initNgrams` —
        # `subwords = [eos_idx]` only, no character n-grams.
        cond do
          token == @eos_token -> [idx]
          args.maxn <= 0 -> [idx]
          true -> [idx | Subwords.compute_indices(token, args, dict)]
        end

      {:ok, _label_idx} ->
        # Known label entry — fastText routes this to its `labels`
        # vector, not the input feature list.
        []

      :error ->
        if String.starts_with?(token, @label_prefix) do
          # Unknown but label-shaped — same fate as a known label.
          []
        else
          # OOV word: subwords only. The reference branch sets
          # `concat = BOW + token + EOW; computeSubwords(concat, line)`,
          # which is exactly what `Subwords.compute_indices/3` does.
          Subwords.compute_indices(token, args, dict)
        end
    end
  end
end
