defmodule Text.Sentiment.Lexicons.AFINNTest do
  use ExUnit.Case, async: true

  alias Text.Sentiment.Lexicons.AFINN

  describe "available/0" do
    test "covers the curated languages from 0.3.0" do
      for tag <- [:en, :da, :fi, :fr, :pl, :sv, :tr, :emoticon] do
        assert tag in AFINN.available()
      end
    end

    test "covers the new bulk-imported languages" do
      # Spot-check a sample across language families and scripts.
      for tag <- [
            :de,
            :es,
            :it,
            :pt,
            :nl,
            :ru,
            :ja,
            :zh,
            :ko,
            :ar,
            :hi,
            :he,
            :uk,
            :vi,
            :th,
            :id,
            :sw,
            :hu,
            :cs,
            :ro
          ] do
        # iw and jw are upstream legacy codes, not :he/:jv
        cond do
          tag == :he -> assert :iw in AFINN.available()
          tag == :jv -> assert :jw in AFINN.available()
          true -> assert tag in AFINN.available()
        end
      end
    end

    test "includes the synthetic :emoji and :emoticon lexicons" do
      assert :emoji in AFINN.available()
      assert :emoticon in AFINN.available()
    end

    test "is sorted" do
      assert AFINN.available() == Enum.sort(AFINN.available())
    end
  end

  describe "lexicon/1" do
    test "returns a non-empty %{token => integer} map for each language" do
      for tag <- AFINN.available() do
        lexicon = AFINN.lexicon(tag)
        assert is_map(lexicon)
        assert map_size(lexicon) > 0, "lexicon for #{inspect(tag)} is empty"

        # Every score is an integer in [-5, 5].
        Enum.each(lexicon, fn {token, score} ->
          assert is_binary(token)
          assert is_integer(score)

          assert score in -5..5,
                 "out-of-range score #{score} for #{inspect(token)} in #{inspect(tag)}"
        end)
      end
    end

    test "raises on an unknown tag" do
      assert_raise ArgumentError, fn -> AFINN.lexicon(:nonexistent_locale) end
    end
  end

  describe "lexicon/1 with :emoji" do
    test "scores common positive emoji at +1 or above" do
      emoji = AFINN.lexicon(:emoji)
      # 😂 face with tears of joy, ❤ heavy black heart, 😍 smiling face with heart eyes
      for cp <- [0x1F602, 0x2764, 0x1F60D] do
        assert emoji[<<cp::utf8>>] >= 1,
               "expected positive score for U+#{Integer.to_string(cp, 16)}"
      end
    end

    test "scores common negative emoji at -1 or below" do
      emoji = AFINN.lexicon(:emoji)
      # 😭 loudly crying face, 💔 broken heart, 😞 disappointed face.
      # 😢 (U+1F622) is excluded — the upstream corpus shows it almost
      # neutral, which matches its actual ambiguous modern usage.
      for cp <- [0x1F62D, 0x1F494, 0x1F61E] do
        assert emoji[<<cp::utf8>>] <= -1,
               "expected negative score for U+#{Integer.to_string(cp, 16)}"
      end
    end
  end

  describe "negators/1" do
    test "returns the curated list when one exists" do
      assert is_list(AFINN.negators(:en))
      assert "not" in AFINN.negators(:en)
    end

    test "returns a non-empty list for several major languages" do
      for tag <- [:en, :de, :es, :fr, :it, :pt, :nl, :ru, :ja, :zh] do
        negators = AFINN.negators(tag)
        assert is_list(negators)
        assert length(negators) > 0, "negators for #{inspect(tag)} is empty"
        Enum.each(negators, &assert(is_binary(&1)))
      end
    end

    test "falls back to the English defaults for unknown tags" do
      negators = AFINN.negators(:nonexistent_locale)
      assert is_list(negators)
      assert "not" in negators
      assert "never" in negators
    end
  end

  describe "has_negators?/1" do
    test "true for languages with curated lists" do
      assert AFINN.has_negators?(:en)
      assert AFINN.has_negators?(:fr)
    end

    test "false for unknown tags" do
      refute AFINN.has_negators?(:nonexistent_locale)
    end
  end
end
