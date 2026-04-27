defmodule Text.IRTest do
  use ExUnit.Case, async: true
  doctest Text.IR
  doctest Text.IR.Corpus

  alias Text.IR
  alias Text.IR.Corpus

  describe "Corpus.new/2" do
    test "indexes basic statistics" do
      docs = ["the cat sat", "the dog sat", "the dog ran"]
      corpus = Corpus.new(docs)

      assert corpus.n_docs == 3
      assert corpus.avg_doc_length == 3.0
      assert Map.get(corpus.document_frequencies, "the") == 3
      assert Map.get(corpus.document_frequencies, "ran") == 1
    end

    test "case folds by default" do
      corpus = Corpus.new(["HELLO world"])
      assert Map.has_key?(corpus.document_frequencies, "hello")
      refute Map.has_key?(corpus.document_frequencies, "HELLO")
    end

    test "fold_case: false preserves case" do
      corpus = Corpus.new(["HELLO world"], fold_case: false)
      assert Map.has_key?(corpus.document_frequencies, "HELLO")
      refute Map.has_key?(corpus.document_frequencies, "hello")
    end

    test "custom tokeniser" do
      # Tokenise on whitespace only — punctuation stays attached.
      corpus =
        Corpus.new(
          ["hello, world"],
          tokenizer: fn s -> String.split(s, ~r/\s+/) end
        )

      assert Map.has_key?(corpus.term_frequencies[0], "hello,")
    end

    test "empty corpus" do
      corpus = Corpus.new([])
      assert corpus.n_docs == 0
      assert corpus.avg_doc_length == 0.0
      assert corpus.document_frequencies == %{}
    end

    test "empty document is fine" do
      corpus = Corpus.new(["hello", ""])
      assert corpus.n_docs == 2
      assert corpus.doc_lengths[0] == 1
      assert corpus.doc_lengths[1] == 0
    end

    test "tokenize_query uses the same pipeline as indexing" do
      corpus = Corpus.new(["one two three"])

      assert Corpus.tokenize_query(corpus, "TWO three!") == ["two", "three"]
    end
  end

  describe "tfidf/3" do
    setup do
      docs = ["the cat sat", "the dog sat", "the dog ran fast", "fox in box"]
      {:ok, corpus: Corpus.new(docs)}
    end

    test "0.0 for missing term", %{corpus: corpus} do
      assert IR.tfidf(corpus, 0, "missing") == 0.0
      assert IR.tfidf(corpus, 0, "FOX") == 0.0
    end

    test "rare terms score higher than common terms (same TF)", %{corpus: corpus} do
      # "fox" appears in 1 doc, "the" in 3. Both have TF=1 in their
      # respective documents. "fox" should score higher.
      assert IR.tfidf(corpus, 3, "fox") > IR.tfidf(corpus, 0, "the")
    end

    test "case-insensitive lookup follows the corpus setting", %{corpus: corpus} do
      assert IR.tfidf(corpus, 0, "Cat") == IR.tfidf(corpus, 0, "cat")
    end

    test "TF=2 scores higher than TF=1 for the same term" do
      docs = ["cat dog", "cat cat dog"]
      corpus = Corpus.new(docs)
      assert IR.tfidf(corpus, 1, "cat") > IR.tfidf(corpus, 0, "cat")
    end
  end

  describe "bm25/4" do
    setup do
      docs = [
        "the cat sat on the mat",
        "the dog sat on the log",
        "the cat ran",
        "fox in box"
      ]

      {:ok, corpus: Corpus.new(docs)}
    end

    test "matching terms score higher than non-matches", %{corpus: corpus} do
      assert IR.bm25(corpus, 0, "cat sat") > IR.bm25(corpus, 3, "cat sat")
    end

    test "0.0 when no query term matches", %{corpus: corpus} do
      assert IR.bm25(corpus, 0, "elephant trunk") == 0.0
    end

    test "longer documents are penalised by length normalisation", %{corpus: corpus} do
      # Doc 2 ("the cat ran") is shorter than doc 0 ("the cat sat on the mat").
      # Both contain "cat" once. The shorter doc should score higher.
      assert IR.bm25(corpus, 2, "cat") > IR.bm25(corpus, 0, "cat")
    end

    test "b: 0.0 disables length normalisation", %{corpus: corpus} do
      # With b=0 the length factor disappears; same-tf documents tie.
      score_short = IR.bm25(corpus, 2, "cat", b: 0.0)
      score_long = IR.bm25(corpus, 0, "cat", b: 0.0)
      assert_in_delta score_short, score_long, 1.0e-9
    end

    test "k1 controls term-frequency saturation" do
      docs = ["cat", "cat cat cat cat cat"]
      corpus = Corpus.new(docs)

      low_k1 = IR.bm25(corpus, 1, "cat", k1: 0.5)
      high_k1 = IR.bm25(corpus, 1, "cat", k1: 4.0)

      # Higher k1 → higher reward for repeated occurrences.
      assert high_k1 > low_k1
    end

    test "accepts pre-tokenised query as a list", %{corpus: corpus} do
      string_score = IR.bm25(corpus, 0, "cat sat")
      list_score = IR.bm25(corpus, 0, ["cat", "sat"])
      assert_in_delta string_score, list_score, 1.0e-9
    end
  end

  describe "search/3" do
    setup do
      docs = [
        "the cat sat on the mat",
        "the dog sat on the log",
        "the cat ran fast",
        "elephants are very large animals",
        "fox in box"
      ]

      {:ok, corpus: Corpus.new(docs), docs: docs}
    end

    test "ranks the most relevant document first", %{corpus: corpus} do
      [{best, _} | _] = IR.search(corpus, "cat sat")
      assert best == 0
    end

    test "returns at most :k results", %{corpus: corpus} do
      assert length(IR.search(corpus, "the", k: 2)) == 2
      assert length(IR.search(corpus, "the", k: 100)) <= corpus.n_docs
    end

    test "drops zero-score documents", %{corpus: corpus} do
      results = IR.search(corpus, "elephant")
      # No doc contains the singular form, so no results.
      assert results == []
    end

    test "scorer: :tfidf option", %{corpus: corpus} do
      bm25_top = corpus |> IR.search("cat sat", scorer: :bm25) |> hd() |> elem(0)
      tfidf_top = corpus |> IR.search("cat sat", scorer: :tfidf) |> hd() |> elem(0)

      # On this small corpus both rankers should agree on the top doc.
      assert bm25_top == tfidf_top
    end

    test "results are sorted descending by score", %{corpus: corpus} do
      scores = corpus |> IR.search("cat sat the") |> Enum.map(&elem(&1, 1))
      assert scores == Enum.sort(scores, :desc)
    end
  end
end
