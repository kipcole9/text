defmodule Text.SentimentTest do
  use ExUnit.Case, async: true
  doctest Text.Sentiment
  doctest Text.Sentiment.Lexicon
  doctest Text.Sentiment.Lexicons.AFINN

  alias Text.Sentiment
  alias Text.Sentiment.Lexicon

  describe "Lexicon.score/3 — core" do
    @lexicon %{"good" => 3, "bad" => -3, "great" => 4, "terrible" => -4, "love" => 3}

    test "returns sum, compound, label, tokens, matched" do
      result = Lexicon.score("good day", @lexicon)

      assert is_float(result.sum)
      assert is_float(result.compound)
      assert result.label == :positive
      assert result.tokens == 2
      assert result.matched == 1
    end

    test "compound is in [-1.0, 1.0] for any input" do
      for text <- [
            "good good good good good good good",
            "bad bad bad bad bad bad bad",
            "neutral text here",
            ""
          ] do
        c = Lexicon.score(text, @lexicon).compound
        assert c >= -1.0 and c <= 1.0
      end
    end

    test "no matches → compound 0.0 and label :neutral" do
      result = Lexicon.score("the cat sat on the mat", @lexicon)
      assert result.sum == 0.0
      assert result.compound == 0.0
      assert result.label == :neutral
      assert result.matched == 0
    end

    test "case-folds lookups by default" do
      r1 = Lexicon.score("GOOD", @lexicon)
      r2 = Lexicon.score("good", @lexicon)
      assert r1.sum == r2.sum
    end

    test "fold_case: false respects case in the lexicon" do
      caps = %{"GOOD" => 3}
      assert Lexicon.score("good", caps, fold_case: false).sum == 0.0
      assert Lexicon.score("GOOD", caps, fold_case: false).sum == 3.0
    end
  end

  describe "Lexicon.score/3 — negation" do
    @lexicon %{"good" => 3, "bad" => -3}

    test "single-word negation flips polarity" do
      assert Lexicon.score("not good", @lexicon).label == :negative
      assert Lexicon.score("not bad", @lexicon).label == :positive
    end

    test "negation operates within a window" do
      # "not" ... "good": within 3-token default window.
      assert Lexicon.score("not very good", @lexicon).label == :negative

      # 4 tokens away: outside the default window.
      result = Lexicon.score("not at all in any way good", @lexicon)
      assert result.label == :positive
    end

    test "custom :negation_window" do
      r1 = Lexicon.score("not really very good", @lexicon, negation_window: 1)
      r2 = Lexicon.score("not really very good", @lexicon, negation_window: 5)
      # With a window of 1, "not" only sees "really" — "good" stays positive.
      assert r1.label == :positive
      # With a window of 5, "not" reaches "good" — flipped negative.
      assert r2.label == :negative
    end

    test "common contractions are recognised" do
      assert Lexicon.score("isn't good", @lexicon).label == :negative
      assert Lexicon.score("don't love", %{"love" => 3}).label == :negative
    end
  end

  describe "Lexicon.score/3 — intensifiers and diminishers" do
    @lexicon %{"good" => 3, "bad" => -3}

    test "intensifier boosts score" do
      base = Lexicon.score("good", @lexicon).sum
      boosted = Lexicon.score("very good", @lexicon).sum
      assert boosted > base
    end

    test "diminisher reduces score" do
      base = Lexicon.score("good", @lexicon).sum
      reduced = Lexicon.score("slightly good", @lexicon).sum
      assert reduced < base
      assert reduced > 0
    end

    test "intensifier and negation compose" do
      # "not very good" — negation reaches the boosted "good".
      neg_boost = Lexicon.score("not very good", @lexicon).sum
      pos_boost = Lexicon.score("very good", @lexicon).sum

      assert neg_boost < 0
      assert pos_boost > 0
    end
  end

  describe "Sentiment.analyze/2 — defaults and language selection" do
    test "default language is English" do
      assert Sentiment.analyze("This is great").language == :en
    end

    test "explicit language picks the bundled lexicon" do
      result = Sentiment.analyze("excellent", language: :fr)
      assert result.language == :fr
      assert result.label == :positive
    end

    test "unknown language falls back to default" do
      result = Sentiment.analyze("good", language: :xx)
      assert result.language == :en
      assert result.label == :positive
    end

    test "custom :fallback_language is honoured" do
      result = Sentiment.analyze("excellent", language: :xx, fallback_language: :fr)
      assert result.language == :fr
      assert result.label == :positive
    end

    test "custom :lexicon overrides language entirely" do
      lex = %{"awesome" => 4}
      result = Sentiment.analyze("That feature is awesome", lexicon: lex)
      assert result.language == :custom
      assert result.label == :positive
    end
  end

  describe "Sentiment.label/2" do
    test "returns just the label" do
      assert Sentiment.label("This is amazing!") == :positive
      assert Sentiment.label("This is awful.") == :negative
      assert Sentiment.label("the package arrived") == :neutral
    end
  end

  describe "Sentiment.lexicon_for/2" do
    test "without options returns a plain bundled lexicon" do
      lex = Sentiment.lexicon_for(:en)
      assert Map.get(lex, "good") == 3
      refute Map.has_key?(lex, ":-)")
    end

    test "with_emoticons: true merges the emoticon lexicon" do
      lex = Sentiment.lexicon_for(:en, with_emoticons: true)
      assert Map.get(lex, "good") == 3
      assert Map.get(lex, ":-)") == 2
    end

    test ":overrides take precedence over bundled entries" do
      lex = Sentiment.lexicon_for(:en, overrides: %{"good" => 100, "magic" => 5})
      assert Map.get(lex, "good") == 100
      assert Map.get(lex, "magic") == 5
    end
  end

  describe "multilingual end-to-end" do
    test "French — positive" do
      assert Sentiment.label("J'adore ce produit, c'est excellent!", language: :fr) == :positive
    end

    test "Swedish — negative" do
      assert Sentiment.label("Detta är en dålig idé.", language: :sv) == :negative
    end

    test "Danish — recognises sentiment-bearing words" do
      result = Sentiment.analyze("dette er fantastisk", language: :da)
      assert result.matched > 0
    end
  end

  describe ":language option accepts atom, string, and Localize.LanguageTag" do
    test "atom input" do
      assert Sentiment.analyze("excellent", language: :fr).language == :fr
    end

    test "string input" do
      assert Sentiment.analyze("excellent", language: "fr").language == :fr
    end

    test "BCP-47 string with region falls back to language subtag" do
      assert Sentiment.analyze("excellent", language: "fr-CA").language == :fr
    end

    test "BCP-47 string with script and region" do
      assert Sentiment.analyze("good", language: "en-Latn-US").language == :en
    end

    test "fallback_language also accepts string and BCP-47" do
      result = Sentiment.analyze("excellent", language: :xx, fallback_language: "fr-CA")
      assert result.language == :fr
      assert result.label == :positive
    end

    if Code.ensure_loaded?(Localize.LanguageTag) do
      @tag :requires_localize
      test "Localize.LanguageTag input" do
        {:ok, tag} = Localize.validate_locale("fr-CA")
        result = Sentiment.analyze("excellent", language: tag)
        assert result.language == :fr
        assert result.label == :positive
      end

      @tag :requires_localize
      test "lexicon_for/2 accepts a LanguageTag" do
        {:ok, tag} = Localize.validate_locale("fr-CA")
        lex = Sentiment.lexicon_for(tag)
        assert Map.get(lex, "excellent") == 4
      end
    end
  end
end
