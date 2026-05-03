defmodule Text.WordCloudTest do
  use ExUnit.Case, async: true
  doctest Text.WordCloud

  alias Text.WordCloud

  describe "terms/2 — frequency backend" do
    test "counts term frequencies and surfaces the most frequent" do
      text = "the cat sat on the mat. the cat ran. the cat slept."

      result = WordCloud.terms(text, scoring: :frequency, language: :en, max_terms: 5)

      assert [%{term: "cat", count: 3, weight: 1.0, kind: :word} | _] = result
    end

    test "filters out stopwords for the resolved language" do
      text = "the cat sat on the mat."

      result = WordCloud.terms(text, scoring: :frequency, language: :en)

      terms = Enum.map(result, & &1.term)
      refute "the" in terms
      refute "on" in terms
      assert "cat" in terms
    end

    test "returns case-folded terms by default" do
      text = "Cat CAT cat"
      result = WordCloud.terms(text, scoring: :frequency, language: :en)

      assert [%{term: "cat", count: 3} | _] = result
    end

    test "case_fold: false preserves case" do
      text = "Cat CAT cat"
      result = WordCloud.terms(text, scoring: :frequency, language: :en, case_fold: false)

      terms = Enum.map(result, & &1.term)
      assert "Cat" in terms
      assert "CAT" in terms
      assert "cat" in terms
    end

    test "respects :max_terms" do
      text = "a b c d e f g h"

      result =
        WordCloud.terms(text, scoring: :frequency, language: nil, max_terms: 3, min_count: 1)

      assert length(result) == 3
    end

    test "respects :min_count" do
      text = "a a a b c d"

      result =
        WordCloud.terms(text, scoring: :frequency, language: nil, min_count: 2)

      assert length(result) == 1
      assert hd(result).term == "a"
    end

    test "weights normalised to [0, 1] with top = 1.0" do
      text = "a a a b b c"

      result =
        WordCloud.terms(text, scoring: :frequency, language: nil)

      weights = Enum.map(result, & &1.weight)
      assert Enum.max(weights) == 1.0
      assert Enum.all?(weights, &(&1 >= 0.0 and &1 <= 1.0))
    end

    test "empty input returns []" do
      assert WordCloud.terms("", scoring: :frequency) == []
      assert WordCloud.terms([], scoring: :frequency) == []
    end

    test "list input is treated as a corpus" do
      docs = ["the cat sat", "the cat ran", "the cat slept"]

      result = WordCloud.terms(docs, scoring: :frequency, language: :en, max_terms: 5)

      assert [%{term: "cat", count: 3} | _] = result
    end

    test "n-gram range produces phrases" do
      text = "machine learning machine learning machine learning"

      result =
        WordCloud.terms(text,
          scoring: :frequency,
          language: nil,
          ngram_range: {2, 2},
          min_count: 1
        )

      terms = Enum.map(result, & &1.term)
      assert "machine learning" in terms
      assert Enum.all?(result, &(&1.kind == :phrase))
    end

    test ":include filters words vs phrases" do
      text =
        "machine learning is a topic. machine learning is hot. machine learning works."

      words_only =
        WordCloud.terms(text,
          scoring: :frequency,
          language: :en,
          ngram_range: {1, 2},
          include: :words,
          min_count: 1
        )

      phrases_only =
        WordCloud.terms(text,
          scoring: :frequency,
          language: :en,
          ngram_range: {1, 2},
          include: :phrases,
          min_count: 1
        )

      assert Enum.all?(words_only, &(&1.kind == :word))
      assert Enum.all?(phrases_only, &(&1.kind == :phrase))
    end
  end

  describe "terms/2 — multilingual stopword filtering" do
    test "French stopwords are filtered when language: :fr" do
      text = "le chat est sur le tapis. le chat dort sur le canapé."

      result = WordCloud.terms(text, scoring: :frequency, language: :fr)

      terms = Enum.map(result, & &1.term)
      refute "le" in terms
      refute "est" in terms
      refute "sur" in terms
      assert "chat" in terms
    end

    test "German stopwords are filtered when language: :de" do
      text = "die Katze sitzt auf der Matte. die Katze schläft auf dem Sofa."

      result = WordCloud.terms(text, scoring: :frequency, language: :de)

      terms = Enum.map(result, & &1.term)
      refute "die" in terms
      refute "auf" in terms
      assert "katze" in terms
    end

    test "stopwords: :none disables filtering" do
      text = "the cat sat"

      result = WordCloud.terms(text, scoring: :frequency, language: :en, stopwords: :none)

      terms = Enum.map(result, & &1.term)
      assert "the" in terms
      assert "cat" in terms
      assert "sat" in terms
    end

    test "stopwords: {:extend, [...]} layers extra words on top" do
      text = "the cat sat on the lorem mat"

      result =
        WordCloud.terms(text,
          scoring: :frequency,
          language: :en,
          stopwords: {:extend, ["lorem"]}
        )

      terms = Enum.map(result, & &1.term)
      refute "the" in terms
      refute "lorem" in terms
      assert "cat" in terms
    end

    test "stopwords: explicit list overrides bundled" do
      text = "the cat sat on a mat"

      result =
        WordCloud.terms(text,
          scoring: :frequency,
          language: :en,
          stopwords: ["cat"]
        )

      terms = Enum.map(result, & &1.term)
      refute "cat" in terms
      assert "the" in terms
    end
  end

  describe "terms/2 — backend resolution" do
    test "raises for an unknown scoring atom" do
      assert_raise ArgumentError, ~r/unknown :scoring backend/, fn ->
        WordCloud.terms("hello world", scoring: :nonexistent)
      end
    end

    test "accepts a custom Backend module" do
      defmodule TestBackend do
        @behaviour Text.WordCloud.Backend
        @impl true
        def score(_input, _options), do: [{"hello", 5, 5, :word}, {"world", 3, 3, :word}]
      end

      result = WordCloud.terms("anything", scoring: TestBackend)

      assert [
               %{term: "hello", count: 5, weight: 1.0},
               %{term: "world", count: 3, weight: 0.6}
             ] = result
    end
  end

  describe "to_d3_cloud/2" do
    defp term(name, weight, count \\ 1, kind \\ :word) do
      %{term: name, weight: weight, count: count, kind: kind}
    end

    test "renames :term to :text and maps weight to size with default range" do
      [a, b] = WordCloud.to_d3_cloud([term("a", 1.0), term("b", 0.0)])

      assert a == %{text: "a", size: 96.0, weight: 1.0, count: 1, kind: :word}
      assert b == %{text: "b", size: 12.0, weight: 0.0, count: 1, kind: :word}
    end

    test "linear scale (default) is the inverse of Layout's font sizing" do
      [_, b, _] =
        WordCloud.to_d3_cloud(
          [term("a", 1.0), term("b", 0.5), term("c", 0.0)],
          font_size_range: {10, 100}
        )

      assert_in_delta b.size, 55.0, 0.001
    end

    test ":sqrt scale produces area-proportional sizing" do
      [_, b, _] =
        WordCloud.to_d3_cloud(
          [term("a", 1.0), term("b", 0.25), term("c", 0.0)],
          font_size_range: {0, 100},
          scale: :sqrt
        )

      assert_in_delta b.size, 50.0, 0.001
    end

    test "sorts by size descending regardless of input order" do
      result =
        WordCloud.to_d3_cloud([
          term("small", 0.1),
          term("big", 1.0),
          term("medium", 0.5)
        ])

      assert Enum.map(result, & &1.text) == ["big", "medium", "small"]
    end

    test "passes through count and kind for d3-cloud callbacks" do
      [phrase, word] =
        WordCloud.to_d3_cloud([
          term("machine learning", 1.0, 12, :phrase),
          term("model", 0.5, 4, :word)
        ])

      assert phrase.count == 12 and phrase.kind == :phrase
      assert word.count == 4 and word.kind == :word
    end
  end
end
