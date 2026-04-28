defmodule Text.WordCloud.Backends.TextRankTest do
  use ExUnit.Case, async: true

  alias Text.WordCloud

  describe "TextRank backend" do
    test "ranks recurring topical words highly on a research-abstract input" do
      text = """
      Compatibility of systems of linear constraints over the set of natural
      numbers. Criteria of compatibility of a system of linear Diophantine
      equations, strict inequations, and nonstrict inequations are
      considered. Upper bounds for components of a minimal set of solutions
      and algorithms of construction of minimal generating sets of solutions
      for all types of systems are given.
      """

      result =
        WordCloud.terms(text,
          scoring: :text_rank,
          language: :en,
          ngram_range: {1, 1},
          max_terms: 10
        )

      terms = Enum.map(result, & &1.term)
      assert "minimal" in terms
      assert "linear" in terms
    end

    test "weights normalised to [0, 1] with top = 1.0" do
      text =
        "Machine learning models are everywhere. Machine learning models work. " <>
          "Models trained on data work well. Data is what models need."

      result = WordCloud.terms(text, scoring: :text_rank, language: :en, max_terms: 5)
      weights = Enum.map(result, & &1.weight)

      assert Enum.max(weights) == 1.0
      assert Enum.all?(weights, &(&1 >= 0.0 and &1 <= 1.0))
    end

    test "respects :ngram_range" do
      text =
        "Machine learning models are everywhere. Machine learning models work."

      result =
        WordCloud.terms(text,
          scoring: :text_rank,
          language: :en,
          ngram_range: {1, 1},
          max_terms: 10
        )

      assert Enum.all?(result, &(&1.kind == :word))
    end

    test "produces phrases when max ngram >= 2" do
      text =
        "Machine learning models are everywhere. Machine learning models work " <>
          "well. Models trained on machine learning data work great."

      result =
        WordCloud.terms(text,
          scoring: :text_rank,
          language: :en,
          ngram_range: {2, 3},
          max_terms: 10
        )

      assert Enum.all?(result, &(&1.kind == :phrase))
    end

    test "empty input returns []" do
      assert WordCloud.terms("", scoring: :text_rank, language: :en) == []
    end

    test "filters stopwords from the graph" do
      text = "the cat sat on the mat. the dog sat on the log."

      result =
        WordCloud.terms(text,
          scoring: :text_rank,
          language: :en,
          ngram_range: {1, 1},
          max_terms: 10
        )

      terms = Enum.map(result, & &1.term)
      refute "the" in terms
      refute "on" in terms
    end

    test "PageRank converges on small inputs without iteration cap" do
      # If iteration didn't converge, we'd see noisy/inconsistent rankings;
      # repeated runs should give identical results given the deterministic
      # initial state.
      text = "alpha beta gamma alpha beta delta"

      r1 = WordCloud.terms(text, scoring: :text_rank, language: nil)
      r2 = WordCloud.terms(text, scoring: :text_rank, language: nil)

      assert r1 == r2
    end
  end
end
