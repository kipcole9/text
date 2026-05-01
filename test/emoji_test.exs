defmodule Text.EmojiTest do
  use ExUnit.Case, async: false
  doctest Text.Emoji

  alias Text.Emoji

  test "extract/1" do
    assert Emoji.extract("a 😀 b 🎉") == ["😀", "🎉"]
    assert Emoji.extract("none") == []
  end

  test "count/1" do
    assert Emoji.count("a 😀 b 🎉") == 2
    assert Emoji.count("none") == 0
  end

  test "contains?/1" do
    assert Emoji.contains?("hi 😀") == true
    assert Emoji.contains?("hi") == false
  end

  test "strip/1" do
    assert Emoji.strip("a 😀 b") == "a  b"
  end

  test "demojize/2 — known emoji" do
    assert Emoji.demojize("hi 😀") == "hi :grinning_face:"
    assert Emoji.demojize("hearts ❤") == "hearts :red_heart:"
  end

  test "demojize/2 — unknown emoji round-trips as itself" do
    assert Emoji.demojize("rare 🪿") == "rare 🪿"
  end

  test "demojize/2 custom delimiter" do
    assert Emoji.demojize("hi 😀", delimiter: "|") == "hi |grinning_face|"
  end

  test "emojize/2" do
    assert Emoji.emojize("hi :grinning_face:") == "hi 😀"
    assert Emoji.emojize("unknown :nonexistent_xyz:") == "unknown :nonexistent_xyz:"
  end

  test "demojize → emojize round-trip on known emoji" do
    text = "I love 🐈 and 🔥 and 💯"
    assert text |> Emoji.demojize() |> Emoji.emojize() == text
  end

  test "add_emoji/1 extends the lookup" do
    assert Emoji.demojize("custom 🦋") == "custom 🦋"
    Emoji.add_emoji(%{"🦋" => "butterfly"})
    assert Emoji.demojize("custom 🦋") == "custom :butterfly:"
    assert Emoji.emojize("see :butterfly:") == "see 🦋"
  end

  describe "sentiment/1" do
    test "returns the full record for a known emoji" do
      record = Emoji.sentiment("😂")
      assert record.emoji == "😂"
      assert record.occurrences > 0
      assert record.score > 0.0
      assert record.score <= 1.0
      assert record.negative + record.neutral + record.positive == record.occurrences
    end

    test "returns nil for unknown emoji" do
      assert Emoji.sentiment("not_an_emoji_string") == nil
    end

    test "negative emoji yields a negative score" do
      assert %{score: s} = Emoji.sentiment("😩")
      assert s < 0.0
    end
  end

  describe "text_sentiment/1" do
    test "returns nil when the text has no scoreable emoji" do
      assert Emoji.text_sentiment("hello world") == nil
    end

    test "averages scores across the emoji in the text" do
      assert {score, count} = Emoji.text_sentiment("yay 😂❤")
      assert count == 2
      assert score > 0.0
    end

    test "skips unknown emoji" do
      # Mix one known + one rare emoji; only the known one contributes
      assert {_score, 1} = Emoji.text_sentiment("😂🪿")
    end
  end
end
