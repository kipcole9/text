defmodule Text.POSTest do
  use ExUnit.Case, async: false

  alias Text.POS

  describe "without :bumblebee compiled, the module raises a helpful message" do
    @describetag skip: Code.ensure_loaded?(Bumblebee)

    test "tag/2 raises ArgumentError-like message" do
      assert_raise RuntimeError, ~r/:bumblebee/, fn ->
        POS.tag("hello world")
      end
    end
  end

  describe "tag/2 against the real model" do
    @describetag :requires_bumblebee_model

    setup do
      POS.reset(:all)
      :ok
    end

    test "tags an English sentence" do
      results = POS.tag("The cat sat on the mat.")

      assert is_list(results)
      assert length(results) > 0

      Enum.each(results, fn {token, tag, score} ->
        assert is_binary(token)
        assert is_atom(tag)
        assert is_float(score)
      end)
    end

    test "identifies nouns and verbs in a simple sentence" do
      results = POS.tag("Cats jump quickly")
      tags = Enum.map(results, fn {_t, tag, _s} -> tag end)
      assert :noun in tags
      assert :verb in tags
    end
  end
end
