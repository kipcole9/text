defmodule Text.WordCloud.Backends.KeyBERTTest do
  use ExUnit.Case, async: false

  alias Text.WordCloud
  alias Text.WordCloud.Backends.KeyBERT

  describe "KeyBERT backend (offline contract)" do
    test "raises a helpful error when :bumblebee is missing" do
      # When :bumblebee is not loaded, the macro-stripped fallback
      # `score/2` raises with installation instructions. We can't
      # toggle Code.ensure_loaded?/1 at test time, so this assertion
      # only fires meaningfully in the no-optional-deps CI matrix
      # entry — but the rest of the suite still validates the
      # Bumblebee path when the dep is loaded.
      unless Code.ensure_loaded?(Bumblebee) do
        assert_raise RuntimeError, ~r/:bumblebee dependency/, fn ->
          KeyBERT.score("hello", [])
        end
      end
    end
  end

  if Code.ensure_loaded?(Bumblebee) do
    @moduletag :requires_bumblebee_model

    @moduletag timeout: 600_000

    setup_all do
      # Drop any cached serving from prior runs so each module run
      # is deterministic.
      KeyBERT.reset()
      :ok
    end

    describe "KeyBERT backend (live model)" do
      test "ranks topical phrases above off-topic ones" do
        text = """
        Quantum computing leverages superposition and entanglement to
        outperform classical algorithms on specific problems. Researchers
        are building quantum processors using superconducting qubits and
        trapped ions to demonstrate quantum advantage.
        """

        result = WordCloud.terms(text, scoring: :key_bert, language: :en, max_terms: 5)

        terms = Enum.map(result, & &1.term)
        # The result should surface phrases related to quantum computing
        # near the top.
        assert Enum.any?(terms, &String.contains?(&1, "quantum"))
        # All weights should be in [0, 1].
        weights = Enum.map(result, & &1.weight)
        assert Enum.max(weights) == 1.0
        assert Enum.all?(weights, &(&1 >= 0.0 and &1 <= 1.0))
      end

      test "respects :ngram_range" do
        text = "machine learning models. machine learning algorithms."

        result =
          WordCloud.terms(text,
            scoring: :key_bert,
            language: :en,
            ngram_range: {1, 1},
            max_terms: 5
          )

        assert Enum.all?(result, &(&1.kind == :word))
      end

      test "empty input returns []" do
        assert WordCloud.terms("", scoring: :key_bert, language: :en) == []
      end
    end
  end
end
