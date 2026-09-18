defmodule Text.Language.Classifier.Fasttext.HashTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Text.Language.Classifier.Fasttext.Hash

  describe "hash/1 — basic invariants" do
    test "empty string returns the FNV offset basis" do
      assert Hash.hash("") == 2_166_136_261
    end

    test "always produces a non-negative uint32" do
      for input <- ["", "a", "the", "<the>", "naïve", "日本", String.duplicate("x", 100)] do
        h = Hash.hash(input)
        assert h >= 0
        assert h < 1 <<< 32
      end
    end

    test "is deterministic" do
      assert Hash.hash("hello") == Hash.hash("hello")
      assert Hash.hash("naïve") == Hash.hash("naïve")
    end

    test "single ASCII byte values match the canonical FNV-1a step" do
      # offset_basis ^ uint32(int8(byte))) * prime, mod 2^32
      assert Hash.hash(<<0>>) == rem(2_166_136_261 * 16_777_619, 1 <<< 32)
      # 0x80 sign-extends to 0xFFFFFF80
      basis_xor_80 = Bitwise.bxor(2_166_136_261, 0xFFFFFF80)
      assert Hash.hash(<<0x80>>) == rem(basis_xor_80 * 16_777_619, 1 <<< 32)
      # 0xFF sign-extends to 0xFFFFFFFF
      basis_xor_ff = Bitwise.bxor(2_166_136_261, 0xFFFFFFFF)
      assert Hash.hash(<<0xFF>>) == rem(basis_xor_ff * 16_777_619, 1 <<< 32)
    end
  end

  describe "hash/1 — differential against fastText reference" do
    @fixture_path Path.expand("../../../fixtures/golden_subwords.json", __DIR__)

    setup do
      if File.exists?(@fixture_path) do
        data = @fixture_path |> File.read!() |> :json.decode()
        {:ok, fixture: data}
      else
        raise "golden_subwords.json is missing. Regenerate it with " <>
                "`python3 priv/scripts/generate_subword_fixtures.py`."
      end
    end

    @tag :requires_lid_176
    test "every recorded subword n-gram hashes to its expected bucket index", %{fixture: f} do
      nwords = f["nwords"]
      bucket = f["bucket"]

      mismatches =
        for entry <- f["entries"],
            {subword, expected_index} <-
              Enum.zip(entry["subwords"], entry["indices"]),
            # Skip the word itself when it lives in the vocab — that index
            # comes from the dictionary lookup, not from this hash.
            expected_index >= nwords do
          actual_index = nwords + rem(Hash.hash(subword), bucket)

          if actual_index == expected_index do
            nil
          else
            %{
              word: entry["word"],
              subword: subword,
              expected: expected_index,
              actual: actual_index
            }
          end
        end
        |> Enum.reject(&is_nil/1)

      assert mismatches == []
    end
  end
end
