defmodule Text.ReadabilityTest do
  use ExUnit.Case, async: true
  doctest Text.Readability

  alias Text.Readability

  @short "The cat sat on the mat."

  @paragraph """
  The implementation of advanced algorithms requires considerable effort.
  Engineers must analyse complex data structures and optimise performance carefully.
  Documentation should be comprehensive yet concise for future maintenance.
  """

  describe "statistics/2" do
    test "counts words and sentences" do
      stats = Readability.statistics(@short)
      assert stats.words == 6
      assert stats.sentences == 1
    end

    test "counts letters separately from characters" do
      stats = Readability.statistics(@short)
      assert stats.letters == 17
      assert stats.characters == 23
    end

    test "computes averages" do
      stats = Readability.statistics(@short)
      assert stats.average_sentence_length == 6.0
      assert stats.average_syllables_per_word == 1.0
    end

    test "polysyllables counts 3+ syllable words" do
      stats = Readability.statistics(@paragraph)
      assert stats.polysyllables >= 5
    end

    test "long_words counts words with 7+ chars" do
      stats = Readability.statistics(@paragraph)
      assert stats.long_words >= 5
    end

    test "empty string returns zeros and zero averages" do
      stats = Readability.statistics("")
      assert stats.words == 0
      assert stats.sentences == 0
      assert stats.average_sentence_length == 0.0
      assert stats.average_syllables_per_word == 0.0
    end
  end

  describe "metric formulas" do
    test "flesch decreases with complexity" do
      simple = Readability.flesch(@short)
      complex = Readability.flesch(@paragraph)
      assert simple > complex
    end

    test "flesch_kincaid grade rises with complexity" do
      simple = Readability.flesch_kincaid(@short)
      complex = Readability.flesch_kincaid(@paragraph)
      assert complex > simple
    end

    test "gunning_fog rises with complex words" do
      simple = Readability.gunning_fog(@short)
      complex = Readability.gunning_fog(@paragraph)
      assert complex > simple
    end

    test "smog rises with polysyllable density" do
      assert Readability.smog(@paragraph) > 0.0
    end

    test "ari rises with longer words and sentences" do
      simple = Readability.ari(@short)
      complex = Readability.ari(@paragraph)
      assert complex > simple
    end

    test "coleman_liau is character-based and rises with complexity" do
      simple = Readability.coleman_liau(@short)
      complex = Readability.coleman_liau(@paragraph)
      assert complex > simple
    end

    test "lix rises with long-word density" do
      simple = Readability.lix(@short)
      complex = Readability.lix(@paragraph)
      assert complex > simple
    end

    test "dale_chall rises with proportion of difficult words" do
      simple = Readability.dale_chall(@short)
      complex = Readability.dale_chall(@paragraph)
      assert complex > simple
    end

    test "dale_chall applies the +3.6365 adjustment when PDW > 0.05" do
      # @paragraph has many words outside the 3000-word easy list.
      stats = Readability.statistics(@paragraph)
      assert stats.difficult_words / stats.words > 0.05

      raw_part =
        0.1579 * (stats.difficult_words / stats.words * 100) +
          0.0496 * (stats.words / stats.sentences)

      assert_in_delta Readability.dale_chall(@paragraph), raw_part + 3.6365, 0.001
    end

    test "spache rises with proportion of unfamiliar words" do
      simple = Readability.spache(@short)
      complex = Readability.spache(@paragraph)
      assert complex > simple
    end
  end

  describe "edge cases" do
    test "empty input returns 0.0 for every metric" do
      assert Readability.flesch("") == 0.0
      assert Readability.flesch_kincaid("") == 0.0
      assert Readability.gunning_fog("") == 0.0
      assert Readability.smog("") == 0.0
      assert Readability.ari("") == 0.0
      assert Readability.coleman_liau("") == 0.0
      assert Readability.lix("") == 0.0
      assert Readability.dale_chall("") == 0.0
      assert Readability.spache("") == 0.0
    end

    test "metrics/2 returns all keys" do
      m = Readability.metrics(@short)

      assert Map.keys(m) |> Enum.sort() ==
               [
                 :ari,
                 :coleman_liau,
                 :dale_chall,
                 :flesch,
                 :flesch_kincaid,
                 :gunning_fog,
                 :lix,
                 :smog,
                 :spache
               ]
    end

    test "metrics/2 matches individual functions" do
      m = Readability.metrics(@short)
      assert m.flesch == Readability.flesch(@short)
      assert m.flesch_kincaid == Readability.flesch_kincaid(@short)
      assert m.ari == Readability.ari(@short)
    end
  end

  describe "passing pre-computed statistics" do
    test "metric functions accept a stats map" do
      stats = Readability.statistics(@short)
      assert Readability.flesch(stats) == Readability.flesch(@short)
      assert Readability.ari(stats) == Readability.ari(@short)
    end
  end
end
