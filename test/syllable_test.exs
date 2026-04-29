defmodule Text.SyllableTest do
  use ExUnit.Case, async: true
  doctest Text.Syllable

  alias Text.Syllable

  describe "count/2 — common single-syllable words" do
    test "monosyllables" do
      for word <- ~w(cat dog run jump rhythm strength bridge) do
        assert Syllable.count(word) == 1, "expected 1 for #{word}"
      end
    end
  end

  describe "count/2 — multisyllable words" do
    test "two-syllable" do
      for word <- ~w(hello apple table candle little simple double) do
        assert Syllable.count(word) == 2, "expected 2 for #{word}"
      end
    end

    test "three-syllable" do
      for word <- ~w(syllable beautiful elephant dynamic computer) do
        assert Syllable.count(word) == 3, "expected 3 for #{word}"
      end
    end

    test "four+ syllables" do
      assert Syllable.count("information") == 4
      assert Syllable.count("communication") == 5
      assert Syllable.count("unbelievable") == 5
    end
  end

  describe "count/2 — silent e and -le endings" do
    test "silent trailing e is not counted" do
      assert Syllable.count("make") == 1
      assert Syllable.count("scale") == 1
      assert Syllable.count("white") == 1
    end

    test "-le after consonant adds a syllable" do
      assert Syllable.count("table") == 2
      assert Syllable.count("candle") == 2
      assert Syllable.count("simple") == 2
    end
  end

  describe "count/2 — exceptions table" do
    test "irregular short words" do
      assert Syllable.count("the") == 1
      assert Syllable.count("queue") == 1
      assert Syllable.count("people") == 2
    end
  end

  describe "count/2 — minimum and edge cases" do
    test "empty string returns 0" do
      assert Syllable.count("") == 0
    end

    test "non-letter input returns 0" do
      assert Syllable.count("123") == 0
      assert Syllable.count("!!!") == 0
    end

    test "leading and trailing punctuation is stripped" do
      assert Syllable.count("hello!") == 2
      assert Syllable.count("'cat'") == 1
    end

    test "case insensitive" do
      assert Syllable.count("Hello") == 2
      assert Syllable.count("SYLLABLE") == 3
    end

    test "minimum of 1 for any word with letters" do
      assert Syllable.count("x") == 1
    end
  end

  describe "count/2 — language option" do
    test "explicit :en works" do
      assert Syllable.count("hello", language: :en) == 2
    end

    test "unsupported language raises" do
      assert_raise ArgumentError, fn -> Syllable.count("bonjour", language: :fr) end
    end
  end

  describe "count_text/2" do
    test "sums tokens" do
      assert Syllable.count_text("the quick brown fox") == 4
      assert Syllable.count_text("hello world") == 3
    end

    test "empty string is zero" do
      assert Syllable.count_text("") == 0
    end

    test "ignores extra whitespace" do
      assert Syllable.count_text("  hello   world  ") == 3
    end
  end
end
