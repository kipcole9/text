defmodule Text.WordCloud.Backends.RAKETest do
  use ExUnit.Case, async: true

  alias Text.WordCloud

  describe "RAKE backend" do
    test "matches the canonical Rose et al. paper example" do
      text = """
      Compatibility of systems of linear constraints over the set of natural
      numbers. Criteria of compatibility of a system of linear Diophantine
      equations, strict inequations, and nonstrict inequations are considered.
      Upper bounds for components of a minimal set of solutions and algorithms
      of construction of minimal generating sets of solutions for all types of
      systems are given.
      """

      result = WordCloud.terms(text, scoring: :rake, language: :en, max_terms: 5)
      terms = Enum.map(result, & &1.term)

      # Top phrases from the paper.
      assert "linear diophantine equations" in terms
      assert "minimal generating sets" in terms
    end

    test "produces phrase-bounded candidates only" do
      text = "the quick brown fox jumps over the lazy dog"

      result =
        WordCloud.terms(text, scoring: :rake, language: :en, ngram_range: {1, 5}, max_terms: 10)

      terms = Enum.map(result, & &1.term)
      # 'the' splits into ["quick brown fox jumps over"] then "lazy dog";
      # all candidates start/end with non-stopwords.
      Enum.each(terms, fn term ->
        tokens = String.split(term)
        refute MapSet.member?(Text.Stopwords.for(:en), List.first(tokens))
        refute MapSet.member?(Text.Stopwords.for(:en), List.last(tokens))
      end)
    end

    test "respects :ngram_range as a length filter" do
      text =
        "machine learning models. machine learning algorithms. machine learning theory."

      result =
        WordCloud.terms(text,
          scoring: :rake,
          language: :en,
          ngram_range: {1, 1},
          max_terms: 10
        )

      assert Enum.all?(result, &(&1.kind == :word))
    end

    test "weights normalised to [0, 1]" do
      text =
        "Compatibility of systems of linear constraints. Criteria of linear " <>
          "Diophantine equations are considered."

      result = WordCloud.terms(text, scoring: :rake, language: :en, max_terms: 5)
      weights = Enum.map(result, & &1.weight)

      assert Enum.max(weights) == 1.0
      assert Enum.all?(weights, &(&1 >= 0.0 and &1 <= 1.0))
    end

    test "empty input returns []" do
      assert WordCloud.terms("", scoring: :rake, language: :en) == []
    end

    test "French text — stopword boundaries respected" do
      text =
        "L'intelligence artificielle transforme l'industrie. " <>
          "L'intelligence artificielle est l'avenir."

      result = WordCloud.terms(text, scoring: :rake, language: :fr, max_terms: 5)
      terms = Enum.map(result, & &1.term)

      assert Enum.any?(terms, &String.contains?(&1, "intelligence"))
      refute "le" in terms
    end
  end
end
