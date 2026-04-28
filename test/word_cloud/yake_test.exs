defmodule Text.WordCloud.Backends.YAKETest do
  use ExUnit.Case, async: true

  alias Text.WordCloud

  describe "YAKE backend (default scoring)" do
    test "ranks 'machine learning' highest in a representative ML paragraph" do
      text = """
      Machine learning is a subset of artificial intelligence. Machine learning
      algorithms build a model based on sample data, known as training data,
      in order to make predictions or decisions. Machine learning has
      applications in email filtering, computer vision, and many other fields.
      """

      result = WordCloud.terms(text, language: :en, max_terms: 10)
      [top | _] = result

      assert top.term == "machine learning"
      assert top.kind == :phrase
      assert top.weight == 1.0
      assert top.count == 3
    end

    test "is the default backend when :scoring is unset" do
      yake_result = WordCloud.terms("alpha beta gamma alpha beta", language: nil)
      explicit = WordCloud.terms("alpha beta gamma alpha beta", language: nil, scoring: :yake)

      assert yake_result == explicit
    end

    test "weights normalised to [0, 1] with top = 1.0" do
      text = "the cat sat on the mat. the cat ran. the cat slept on the sofa."

      result = WordCloud.terms(text, language: :en, max_terms: 5)

      weights = Enum.map(result, & &1.weight)
      assert Enum.max(weights) == 1.0
      assert Enum.all?(weights, &(&1 >= 0.0 and &1 <= 1.0))
    end

    test "respects :ngram_range — unigrams only" do
      text = "machine learning models. machine learning algorithms. machine learning theory."

      result =
        WordCloud.terms(text,
          language: :en,
          ngram_range: {1, 1},
          max_terms: 10
        )

      assert Enum.all?(result, &(&1.kind == :word))
    end

    test "respects :ngram_range — bigrams only" do
      text = "machine learning models. machine learning algorithms. machine learning theory."

      result =
        WordCloud.terms(text,
          language: :en,
          ngram_range: {2, 2},
          max_terms: 10
        )

      assert Enum.all?(result, &(&1.kind == :phrase))
    end

    test "phrases must start and end with a non-stopword" do
      text = "the cat is on the mat. the dog is on the log. the cat is happy."

      result =
        WordCloud.terms(text,
          language: :en,
          ngram_range: {2, 3},
          max_terms: 20
        )

      # No phrase should start or end with a stopword.
      Enum.each(result, fn r ->
        tokens = String.split(r.term)
        refute MapSet.member?(Text.Stopwords.for(:en), List.first(tokens))
        refute MapSet.member?(Text.Stopwords.for(:en), List.last(tokens))
      end)
    end

    test "interior stopwords are allowed in phrases" do
      text =
        "subset of artificial intelligence. domain of artificial intelligence. application of artificial intelligence."

      result =
        WordCloud.terms(text,
          language: :en,
          ngram_range: {1, 4},
          max_terms: 10
        )

      terms = Enum.map(result, & &1.term)
      # "of artificial" / "of artificial intelligence" — interior stopword is
      # tolerated. We expect at least one term containing "of" between non-stopwords.
      assert Enum.any?(terms, &String.contains?(&1, " of "))
    end

    test "single-word document produces a non-empty result" do
      assert [%{term: "rhinoceros"} | _] = WordCloud.terms("rhinoceros", language: :en)
    end

    test "empty input returns []" do
      assert WordCloud.terms("", language: :en) == []
    end

    test "preserves case when case_fold: false" do
      text = "Apple released a new product. Apple is innovative. Apple stocks rose."

      result =
        WordCloud.terms(text,
          language: :en,
          case_fold: false,
          ngram_range: {1, 1},
          max_terms: 5
        )

      terms = Enum.map(result, & &1.term)
      assert "Apple" in terms
    end

    test "French text — stopwords filtered, distinctive content surfaces" do
      text = """
      L'intelligence artificielle est une technologie révolutionnaire.
      L'intelligence artificielle transforme l'industrie. L'intelligence
      artificielle est l'avenir.
      """

      result = WordCloud.terms(text, language: :fr, max_terms: 5)

      terms = Enum.map(result, & &1.term)
      # The recurring phrase should surface high. The exact form depends on
      # tokenization of "L'intelligence" — verify that "intelligence" or
      # "intelligence artificielle" appears prominently.
      assert Enum.any?(terms, &String.contains?(&1, "intelligence"))
      refute "le" in terms
      refute "la" in terms
    end
  end
end
