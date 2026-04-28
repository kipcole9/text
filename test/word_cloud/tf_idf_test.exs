defmodule Text.WordCloud.Backends.TFIDFTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Text.WordCloud

  describe "TF-IDF backend with reference corpus" do
    test "surfaces terms distinctive to the foreground" do
      foreground =
        "Cats are common household pets. Cats love to nap. Quantum cats exist in many states at once."

      background = [
        "Cats are common household pets that purr.",
        "Cats love to nap in sunny spots.",
        "Dogs are loyal companion animals that bark.",
        "Birds fly through the sky and sing.",
        "Fish swim in water and have scales."
      ]

      result =
        WordCloud.terms(foreground,
          scoring: :tf_idf,
          language: :en,
          reference_corpus: background,
          max_terms: 5
        )

      terms = Enum.map(result, & &1.term)
      assert "quantum" in terms
      assert "cats" in terms
      # "common" appears in the foreground and in 1 of 5 background docs;
      # it should still appear but lower than "quantum".
      [top | _] = result
      assert top.term in ["cats", "quantum"]
    end

    test "accepts a precomputed IDF map" do
      idf_map = %{
        "alpha" => 5.0,
        "beta" => 3.0,
        "gamma" => 1.0
      }

      result =
        WordCloud.terms("alpha beta gamma alpha",
          scoring: :tf_idf,
          language: nil,
          reference_corpus: idf_map,
          max_terms: 5
        )

      # alpha: 2 * 5.0 = 10.0
      # beta:  1 * 3.0 = 3.0
      # gamma: 1 * 1.0 = 1.0
      assert [%{term: "alpha"}, %{term: "beta"}, %{term: "gamma"}] = result
    end

    test "warns when no reference corpus is provided" do
      output =
        capture_io(:stderr, fn ->
          WordCloud.terms("alpha beta gamma alpha",
            scoring: :tf_idf,
            language: nil,
            max_terms: 5
          )
        end)

      assert output =~ "no :reference_corpus"
    end

    test "weights normalised to [0, 1]" do
      foreground = "alpha beta gamma alpha beta"
      background = ["other words", "different document", "third doc"]

      result =
        WordCloud.terms(foreground,
          scoring: :tf_idf,
          language: nil,
          reference_corpus: background,
          max_terms: 5
        )

      weights = Enum.map(result, & &1.weight)
      assert Enum.max(weights) == 1.0
      assert Enum.all?(weights, &(&1 >= 0.0 and &1 <= 1.0))
    end

    test "raises if the reference corpus is empty" do
      assert_raise ArgumentError, ~r/empty/, fn ->
        WordCloud.terms("hello world",
          scoring: :tf_idf,
          reference_corpus: [],
          language: nil
        )
      end
    end

    test "respects :ngram_range when explicitly set" do
      foreground = "machine learning machine learning machine learning"
      background = ["other text", "another document"]

      result =
        WordCloud.terms(foreground,
          scoring: :tf_idf,
          language: nil,
          reference_corpus: background,
          ngram_range: {2, 2},
          min_count: 1,
          max_terms: 5
        )

      assert Enum.all?(result, &(&1.kind == :phrase))
    end

    test "default ngram_range is {1, 1}" do
      foreground = "alpha beta gamma"
      background = ["other text"]

      result =
        WordCloud.terms(foreground,
          scoring: :tf_idf,
          language: nil,
          reference_corpus: background,
          max_terms: 10
        )

      assert Enum.all?(result, &(&1.kind == :word))
    end
  end
end
