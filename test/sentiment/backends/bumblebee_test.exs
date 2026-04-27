defmodule Text.Sentiment.Backends.BumblebeeTest do
  # Async would race on the :persistent_term cache. Sync to keep
  # backend reset between tests deterministic.
  use ExUnit.Case, async: false

  alias Text.Sentiment

  describe "Backend.resolve/1 — routing" do
    test "default is Lexicon when no option / config" do
      Application.delete_env(:text, :sentiment_backend)
      assert Sentiment.Backend.resolve([]) == Sentiment.Backends.Lexicon
    end

    test ":backend option overrides default" do
      assert Sentiment.Backend.resolve(backend: Sentiment.Backends.Bumblebee) ==
               Sentiment.Backends.Bumblebee
    end

    test "application config overrides default but loses to :backend option" do
      Application.put_env(:text, :sentiment_backend, Sentiment.Backends.Bumblebee)

      try do
        assert Sentiment.Backend.resolve([]) == Sentiment.Backends.Bumblebee

        assert Sentiment.Backend.resolve(backend: Sentiment.Backends.Lexicon) ==
                 Sentiment.Backends.Lexicon
      after
        Application.delete_env(:text, :sentiment_backend)
      end
    end
  end

  describe "Backends.Bumblebee.analyze/2 — needs network + model download" do
    @describetag :requires_bumblebee_model

    setup do
      Sentiment.Backends.Bumblebee.reset(:all)
      :ok
    end

    test "returns the standard result shape" do
      result = Sentiment.Backends.Bumblebee.analyze("This is a fantastic product!")

      assert result.label in [:positive, :negative, :neutral]
      assert is_float(result.compound)
      assert result.compound >= -1.0 and result.compound <= 1.0
      assert result.backend == Sentiment.Backends.Bumblebee
      assert is_binary(result.model)
      assert is_map(result.scores)
      assert Map.has_key?(result.scores, :positive)
      assert Map.has_key?(result.scores, :negative)
    end

    test "positive English input scores positive" do
      result = Sentiment.Backends.Bumblebee.analyze("I absolutely love this!")
      assert result.label == :positive
      assert result.compound > 0
    end

    test "negative English input scores negative" do
      result = Sentiment.Backends.Bumblebee.analyze("This was a terrible, awful experience.")
      assert result.label == :negative
      assert result.compound < 0
    end

    test "multilingual: French positive" do
      result = Sentiment.Backends.Bumblebee.analyze("J'adore ce produit, c'est excellent!")
      assert result.label == :positive
    end

    test "multilingual: Spanish positive" do
      result = Sentiment.Backends.Bumblebee.analyze("¡Me encanta este lugar, es maravilloso!")
      assert result.label == :positive
    end

    test "Sentiment.analyze with explicit backend" do
      result = Sentiment.analyze("Great product!", backend: Sentiment.Backends.Bumblebee)
      assert result.backend == Sentiment.Backends.Bumblebee
      assert result.label == :positive
    end

    test "result includes the resolved language when provided" do
      {:ok, tag} = Localize.validate_locale("fr-CA")

      result =
        Sentiment.Backends.Bumblebee.analyze(
          "Ce produit est excellent",
          language: tag
        )

      assert result.language == :fr
    end
  end
end
