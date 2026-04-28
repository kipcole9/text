defmodule Text.Language.Classifier.Fasttext.SubwordsTest do
  use ExUnit.Case, async: true

  alias Text.Language.Classifier.Fasttext.{Args, Dictionary, Subwords}

  describe "compute_ngrams/3 — basic shape" do
    test "ASCII word, minn=2 maxn=4" do
      assert Subwords.compute_ngrams("the", 2, 4) ==
               ["<t", "<th", "<the", "th", "the", "the>", "he", "he>", "e>"]
    end

    test "single-character word still emits the boundary-trim rule" do
      # n=1 ngrams that include only the BOW or EOW marker are dropped:
      # "<" alone (i==0) and ">" alone (j==size). For "a" with minn=1,
      # maxn=1, only "a" itself remains as a 1-char ngram.
      assert Subwords.compute_ngrams("a", 1, 1) == ["a"]
    end

    test "minn==maxn==2 produces only 2-char ngrams" do
      assert Subwords.compute_ngrams("abc", 2, 2) == ["<a", "ab", "bc", "c>"]
    end

    test "UTF-8 multibyte characters count as one character, not many bytes" do
      # "日本" — each codepoint is 3 UTF-8 bytes. With minn=2, maxn=2,
      # the only 2-character n-grams are "<日", "日本", "本>".
      assert Subwords.compute_ngrams("日本", 2, 2) == [
               "<日",
               "日本",
               "本>"
             ]
    end

    test "diacritic combining sequences are byte-included" do
      # "é" = 0xC3 0xA9 (single codepoint). "ée" with minn=2,maxn=2
      # produces "<é", "ée", "e>".
      assert Subwords.compute_ngrams("ée", 2, 2) == ["<é", "ée", "e>"]
    end

    test "empty word still produces the boundary pair if minn allows" do
      # The framed string is "<>" — 2 bytes. With minn=2,maxn=2, the only
      # candidate is "<>" itself. The reference's filter does NOT drop
      # this case (n==2, not n==1), so it is emitted.
      assert Subwords.compute_ngrams("", 2, 2) == ["<>"]
    end
  end

  describe "compute_indices/3 — pushHash regimes" do
    setup do
      args = %Args{
        dim: 16,
        ws: 0,
        epoch: 0,
        min_count: 0,
        neg: 0,
        word_ngrams: 1,
        loss: :softmax,
        model: :sup,
        bucket: 100,
        minn: 2,
        maxn: 4,
        lr_update_rate: 0,
        t: 0.0
      }

      base_dict = %Dictionary{
        size: 1000,
        nwords: 1000,
        nlabels: 0,
        ntokens: 0,
        pruneidx_size: -1,
        entries: [],
        word_to_index: %{},
        pruneidx: %{}
      }

      {:ok, args: args, dict: base_dict}
    end

    test "unpruned (-1) regime: every n-gram contributes one index", %{args: args, dict: dict} do
      indices = Subwords.compute_indices("the", args, dict)
      assert length(indices) == 9

      Enum.each(indices, fn idx ->
        assert idx >= dict.nwords
        assert idx < dict.nwords + args.bucket
      end)
    end

    test "pruneidx_size==0 regime: drops every n-gram", %{args: args, dict: dict} do
      dict = %{dict | pruneidx_size: 0}
      assert Subwords.compute_indices("the", args, dict) == []
    end

    test "populated pruneidx: only mapped hashes survive", %{args: args, dict: dict} do
      dict = %{
        dict
        | pruneidx_size: 1,
          pruneidx: %{0 => 7, 50 => 8}
      }

      indices = Subwords.compute_indices("the", args, dict)
      assert Enum.all?(indices, fn i -> i in [dict.nwords + 7, dict.nwords + 8] end)
    end
  end

  describe "differential against fastText reference" do
    @fixture_path Path.expand("../../../fixtures/golden_subwords.json", __DIR__)

    setup do
      if File.exists?(@fixture_path) do
        data = @fixture_path |> File.read!() |> :json.decode()
        {:ok, fixture: data}
      else
        {:skip, "skipping; generate via `python3 priv/scripts/generate_subword_fixtures.py`"}
      end
    end

    @tag :requires_lid_176
    test "compute_ngrams matches reference n-gram order for every word", %{fixture: f} do
      nwords = f["nwords"]

      mismatches =
        for entry <- f["entries"], reduce: [] do
          acc ->
            # Reference subwords list contains the word itself first when
            # the word is in vocab; drop it to compare against the n-gram
            # output.
            reference_ngrams = strip_word_prefix(entry["subwords"], entry["indices"], nwords)
            ours = Subwords.compute_ngrams(entry["word"], f["minn"], f["maxn"])

            if reference_ngrams == ours do
              acc
            else
              [%{word: entry["word"], expected: reference_ngrams, actual: ours} | acc]
            end
        end

      assert mismatches == []
    end

    @tag :requires_lid_176
    test "compute_indices matches reference indices for every word", %{fixture: f} do
      args = %Args{
        dim: 16,
        ws: 0,
        epoch: 0,
        min_count: 0,
        neg: 0,
        word_ngrams: 1,
        loss: :softmax,
        model: :sup,
        bucket: f["bucket"],
        minn: f["minn"],
        maxn: f["maxn"],
        lr_update_rate: 0,
        t: 0.0
      }

      dict = %Dictionary{
        size: f["nwords"] + f["nlabels"],
        nwords: f["nwords"],
        nlabels: f["nlabels"],
        ntokens: 0,
        pruneidx_size: -1,
        entries: [],
        word_to_index: %{},
        pruneidx: %{}
      }

      mismatches =
        for entry <- f["entries"], reduce: [] do
          acc ->
            reference_indices =
              strip_word_index_prefix(entry["indices"], dict.nwords)

            ours = Subwords.compute_indices(entry["word"], args, dict)

            if reference_indices == ours do
              acc
            else
              [%{word: entry["word"], expected: reference_indices, actual: ours} | acc]
            end
        end

      assert mismatches == []
    end
  end

  defp strip_word_prefix(subwords, indices, nwords) do
    case {subwords, indices} do
      {[_first_subword | rest], [first_index | _]} when first_index < nwords ->
        rest

      _ ->
        subwords
    end
  end

  defp strip_word_index_prefix(indices, nwords) do
    case indices do
      [first_index | rest] when first_index < nwords -> rest
      _ -> indices
    end
  end
end
