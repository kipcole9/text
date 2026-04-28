defmodule Text.CollocationTest do
  use ExUnit.Case, async: true
  doctest Text.Collocation

  alias Text.Collocation

  describe "bigrams/2 — basic behaviour" do
    test "extracts repeated bigrams from a token list" do
      tokens = ~w[a b a b a b]
      assert [{["a", "b"], _} | _] = Collocation.bigrams(tokens, min_count: 2)
    end

    test "respects :min_count" do
      tokens = ~w[a b c d a b]
      assert [{["a", "b"], _}] = Collocation.bigrams(tokens, min_count: 2)
    end

    test "respects :k limit" do
      text = "a b c d e f g h"
      results = Collocation.bigrams(text, min_count: 1, k: 3)
      assert length(results) == 3
    end

    test "k: :infinity returns everything" do
      text = "a b c d e f g h"
      results = Collocation.bigrams(text, min_count: 1, k: :infinity)
      # 7 distinct bigrams in "a b c d e f g h"
      assert length(results) == 7
    end

    test "accepts string input via tokenizer" do
      text = "the cat sat. the cat ran."

      assert [{[a, b], _} | _] =
               Collocation.bigrams(text, min_count: 2, k: 1)

      assert {a, b} == {"the", "cat"}
    end

    test "case folding is on by default" do
      tokens = ~w[The cat THE cat the cat]
      [{[t1, t2], _} | _] = Collocation.bigrams(tokens, min_count: 2, k: 1)
      assert t1 == "the"
      assert t2 == "cat"
    end

    test "fold_case: false preserves case" do
      tokens = ~w[The cat THE cat]
      results = Collocation.bigrams(tokens, min_count: 1, fold_case: false)
      pairs = Enum.map(results, fn {pair, _} -> pair end)
      assert ["The", "cat"] in pairs
      assert ["THE", "cat"] in pairs
    end

    test "stopwords drop bigrams containing any listed token" do
      text =
        "the cat sat on the mat. the dog sat on the log. machine learning is great. machine learning rules."

      results =
        Collocation.bigrams(text,
          min_count: 2,
          stopwords: ~w[the on a is],
          k: 5
        )

      pairs = Enum.map(results, fn {p, _} -> p end)
      refute Enum.any?(pairs, fn pair -> "the" in pair end)
      assert ["machine", "learning"] in pairs
    end
  end

  describe "bigrams/2 — measures" do
    test ":frequency returns raw counts" do
      tokens = ~w[a b a b c d c d c d]
      results = Collocation.bigrams(tokens, measure: :frequency, min_count: 1)

      counts = Map.new(results, fn {pair, score} -> {pair, score} end)
      assert counts[["a", "b"]] == 2
      assert counts[["c", "d"]] == 3
    end

    test ":pmi rewards exclusive co-occurrence" do
      # "a b" appears 5 times; a never appears outside "a b" pairs.
      # PMI should be high — the two terms always come together.
      tokens = ~w[a b a b a b a b a b]
      [{["a", "b"], pmi}] = Collocation.bigrams(tokens, measure: :pmi, min_count: 5)
      assert pmi > 0.0
    end

    test ":log_likelihood is non-negative for observed bigrams" do
      tokens =
        ~w[the cat sat on the mat the cat ran fast the cat slept on the mat]

      results = Collocation.bigrams(tokens, measure: :log_likelihood, min_count: 2)

      Enum.each(results, fn {_pair, score} ->
        assert score >= 0.0
      end)
    end

    test ":log_likelihood and :pmi rank top bigram identically for clear cases" do
      # When one bigram is clearly dominant, both measures put it first.
      text =
        "machine learning is a topic. machine learning is hot. machine learning models work. machine learning theory matters. machine learning data science."

      [{ll_top, _} | _] = Collocation.bigrams(text, measure: :log_likelihood, min_count: 3)
      [{pmi_top, _} | _] = Collocation.bigrams(text, measure: :pmi, min_count: 3)

      assert ll_top == ["machine", "learning"]
      assert pmi_top == ["machine", "learning"]
    end
  end

  describe "bigrams/2 — edge cases" do
    test "empty input" do
      assert Collocation.bigrams("", min_count: 1) == []
      assert Collocation.bigrams([], min_count: 1) == []
    end

    test "single token has no bigrams" do
      assert Collocation.bigrams(["only"], min_count: 1) == []
    end

    test "bigrams below min_count are filtered" do
      assert Collocation.bigrams(~w[a b c d], min_count: 2) == []
    end
  end
end
