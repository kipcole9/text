defmodule Text.Language.Classifier.Fasttext.ScriptDetectorTest do
  use ExUnit.Case, async: true

  alias Text.Language.Classifier.Fasttext.ScriptDetector

  describe "detect/1" do
    test "Latin script for plain English" do
      assert ScriptDetector.detect("Hello world") == :Latn
    end

    test "Cyrillic script for Russian" do
      assert ScriptDetector.detect("Привет мир") == :Cyrl
    end

    test "Greek script for Greek" do
      assert ScriptDetector.detect("Γεια σου κόσμε") == :Grek
    end

    test "Arabic script for Arabic" do
      assert ScriptDetector.detect("مرحبا بالعالم") == :Arab
    end

    test "Hebrew script for Hebrew" do
      assert ScriptDetector.detect("שלום עולם") == :Hebr
    end

    test "Devanagari script for Hindi" do
      assert ScriptDetector.detect("नमस्ते दुनिया") == :Deva
    end

    test "Tamil script for Tamil" do
      assert ScriptDetector.detect("வணக்கம் உலகம்") == :Taml
    end

    test "Thai script for Thai" do
      assert ScriptDetector.detect("สวัสดีชาวโลก") == :Thai
    end

    test "Han script for Chinese ideographs (only shared codepoints)" do
      # "你好世界" uses only shared Hans/Hant codepoints, so detection
      # falls back to the generic :Hani.
      assert ScriptDetector.detect("你好世界") == :Hani
    end

    test "Simplified Han text resolves to :Hans" do
      assert ScriptDetector.detect("你好世界，这是简体中文。") == :Hans
      assert ScriptDetector.detect("国家学校时间") == :Hans
    end

    test "Traditional Han text resolves to :Hant" do
      assert ScriptDetector.detect("你好世界，這是繁體中文。") == :Hant
      assert ScriptDetector.detect("國家學校時間") == :Hant
    end

    test "han_variant/1 works on already-Han text" do
      assert ScriptDetector.han_variant("国学时来") == :Hans
      assert ScriptDetector.han_variant("國學時來") == :Hant
      assert ScriptDetector.han_variant("你好世界") == :Hani
      assert ScriptDetector.han_variant("Hello world") == :Hani
    end

    test "Hiragana script for predominantly hiragana text" do
      assert ScriptDetector.detect("こんにちは") == :Hira
    end

    test "Hangul script for Korean" do
      assert ScriptDetector.detect("안녕하세요") == :Hang
    end

    test "common-script-only input returns Zyyy" do
      assert ScriptDetector.detect("123 !!!") == :Zyyy
    end

    test "empty input returns Zyyy" do
      assert ScriptDetector.detect("") == :Zyyy
    end

    test "ignores punctuation when picking dominant script" do
      assert ScriptDetector.detect("Привет!") == :Cyrl
    end

    test "mixed input returns the more frequent script" do
      assert ScriptDetector.detect("Hello мир") == :Latn
      assert ScriptDetector.detect("hi Привет мир там") == :Cyrl
    end
  end

  describe "tally/1" do
    test "counts each script independently" do
      tally = ScriptDetector.tally("Hello мир")
      assert tally[:Latn] == 5
      assert tally[:Cyrl] == 3
    end

    test "drops common-script bucket" do
      tally = ScriptDetector.tally("Hello, world!")
      assert tally[:Latn] == 10
      assert Map.has_key?(tally, :Zyyy) == false
    end
  end
end
