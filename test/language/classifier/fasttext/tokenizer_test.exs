defmodule Text.Language.Classifier.Fasttext.TokenizerTest do
  use ExUnit.Case, async: true

  alias Text.Language.Classifier.Fasttext.Tokenizer

  describe "tokenize/1" do
    test "splits on space" do
      assert Tokenizer.tokenize("hello world") == ["hello", "world"]
    end

    test "collapses runs of whitespace" do
      assert Tokenizer.tokenize("  hello   world  ") == ["hello", "world"]
    end

    test "handles every whitespace byte fastText recognises" do
      input =
        IO.iodata_to_binary([
          "a",
          ?\s,
          "b",
          ?\t,
          "c",
          ?\n,
          "d",
          ?\r,
          "e",
          ?\v,
          "f",
          ?\f,
          "g",
          0,
          "h"
        ])

      assert Tokenizer.tokenize(input) == ["a", "b", "c", "d", "e", "f", "g", "h"]
    end

    test "leading and trailing whitespace produce no empty tokens" do
      assert Tokenizer.tokenize("   foo bar   ") == ["foo", "bar"]
    end

    test "empty string returns empty list" do
      assert Tokenizer.tokenize("") == []
    end

    test "whitespace-only input returns empty list" do
      assert Tokenizer.tokenize("   \t\n\r\v\f") == []
    end

    test "single token is preserved" do
      assert Tokenizer.tokenize("supercalifragilistic") == ["supercalifragilistic"]
    end

    test "non-ASCII tokens are returned as-is at the byte level" do
      assert Tokenizer.tokenize("日本語 中文") == ["日本語", "中文"]
      assert Tokenizer.tokenize("naïve café") == ["naïve", "café"]
    end

    test "multibyte characters are not split internally" do
      # "你好" — both codepoints are 3 bytes each. None of the bytes
      # in their UTF-8 encoding are in the whitespace set, so the token
      # stays intact.
      assert Tokenizer.tokenize("你好") == ["你好"]
    end

    test "trailing token without trailing whitespace is flushed" do
      assert Tokenizer.tokenize("a b c") == ["a", "b", "c"]
      assert Tokenizer.tokenize("xyz") == ["xyz"]
    end
  end
end
