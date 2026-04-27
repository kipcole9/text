defmodule Text.KWICTest do
  use ExUnit.Case, async: true
  doctest Text.KWIC

  alias Text.KWIC
  alias Text.KWIC.Match

  describe "concordance/3" do
    test "returns one match per occurrence" do
      text = "the cat sat. the cat ran. the cat slept."
      matches = KWIC.concordance(text, "cat")
      assert length(matches) == 3
    end

    test "captures left and right context" do
      text = "the quick brown fox jumped over"
      [match] = KWIC.concordance(text, "fox", context: 2)

      assert match.term == "fox"
      assert match.left == ["quick", "brown"]
      assert match.right == ["jumped", "over"]
    end

    test "context truncates at document edges" do
      text = "fox jumped over"
      [match] = KWIC.concordance(text, "fox", context: 5)
      assert match.left == []
      assert match.right == ["jumped", "over"]

      text2 = "the cat fox"
      [match2] = KWIC.concordance(text2, "fox", context: 5)
      assert match2.left == ["the", "cat"]
      assert match2.right == []
    end

    test "case-insensitive by default" do
      text = "The Cat sat. the cat ran."
      matches = KWIC.concordance(text, "cat")
      assert length(matches) == 2
    end

    test "preserves original casing in match output" do
      text = "The Cat sat"
      [match] = KWIC.concordance(text, "cat")
      assert match.term == "Cat"
    end

    test "case_sensitive: true" do
      text = "The Cat sat. the cat ran."
      matches = KWIC.concordance(text, "cat", case_sensitive: true)
      assert length(matches) == 1
      assert hd(matches).term == "cat"
    end

    test "no matches returns empty list" do
      assert KWIC.concordance("nothing here", "missing") == []
    end

    test "position is the zero-based token index" do
      text = "a b c fox d e"
      [match] = KWIC.concordance(text, "fox")
      assert match.position == 3
    end

    test "context: 0 returns no surrounding tokens" do
      text = "the cat sat"
      [match] = KWIC.concordance(text, "cat", context: 0)
      assert match.left == []
      assert match.right == []
      assert match.term == "cat"
    end

    test "custom tokenizer" do
      text = "a:b:cat:d:e"

      matches =
        KWIC.concordance(text, "cat",
          context: 1,
          tokenizer: fn s -> String.split(s, ":") end
        )

      assert length(matches) == 1
      assert hd(matches).left == ["b"]
      assert hd(matches).right == ["d"]
    end
  end

  describe "format/2" do
    test "default separator" do
      match = %Match{position: 0, left: ["the"], term: "fox", right: ["jumped"]}
      assert KWIC.format(match) == "the | fox | jumped"
    end

    test "custom separator" do
      match = %Match{position: 0, left: ["the"], term: "fox", right: ["jumped"]}
      assert KWIC.format(match, separator: " ~ ") == "the ~ fox ~ jumped"
    end

    test "width pads the left context" do
      match = %Match{position: 0, left: ["a", "b"], term: "fox", right: ["c"]}
      formatted = KWIC.format(match, width: 10)
      # "a b" padded to 10 chars on the left.
      assert String.starts_with?(formatted, "       a b")
    end

    test "empty left/right contexts" do
      match = %Match{position: 0, left: [], term: "fox", right: []}
      assert KWIC.format(match) == " | fox | "
    end
  end
end
