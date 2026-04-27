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

    test "Han script for Chinese ideographs" do
      assert ScriptDetector.detect("你好世界") == :Hani
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
