defmodule Text.WordCloud.LayoutTest do
  use ExUnit.Case, async: true
  doctest Text.WordCloud.Layout

  alias Text.WordCloud.Layout

  defp term(name, weight, kind \\ :word) do
    %{term: name, weight: weight, count: 1, kind: kind}
  end

  describe "layout/2" do
    test "places the top-weighted term at the canvas centre" do
      terms = [term("alpha", 1.0)]
      [p] = Layout.layout(terms, width: 800, height: 600)

      assert p.x == 400.0
      assert p.y == 300.0
    end

    test "font_size scales linearly within :font_size_range" do
      terms = [term("a", 1.0), term("b", 0.5), term("c", 0.0)]
      [pa, pb, pc] = Layout.layout(terms, font_size_range: {10, 100})

      assert pa.font_size == 100.0
      assert_in_delta pb.font_size, 55.0, 0.001
      assert pc.font_size == 10.0
    end

    test "non-overlapping placements" do
      # Generate enough terms to force spiral placement; the result must
      # have no two boxes overlapping.
      terms = Enum.map(1..15, fn i -> term("term#{i}", 1.0 - i / 20) end)
      placements = Layout.layout(terms, width: 1000, height: 800)

      # Build [{left, top, right, bottom}] for collision testing.
      boxes =
        Enum.map(placements, fn p ->
          {p.x - p.width / 2, p.y - p.height / 2, p.x + p.width / 2, p.y + p.height / 2}
        end)

      # Pairwise overlap test.
      pairs =
        for {a, i} <- Enum.with_index(boxes), {b, j} <- Enum.with_index(boxes), i < j, do: {a, b}

      Enum.each(pairs, fn {a, b} ->
        assert not boxes_overlap?(a, b),
               "boxes overlap: #{inspect(a)} vs #{inspect(b)}"
      end)
    end

    test "drops terms that don't fit on a tiny canvas" do
      terms = Enum.map(1..50, fn i -> term("verylongterm#{i}", 1.0 - i / 100) end)
      placements = Layout.layout(terms, width: 100, height: 60, font_size_range: {12, 24})

      assert length(placements) < length(terms)
    end

    test "returns terms in placement order (top weight first)" do
      terms = [term("z", 0.5), term("a", 1.0), term("m", 0.8)]
      placements = Layout.layout(terms)

      weights = Enum.map(placements, & &1.weight)
      assert weights == [1.0, 0.8, 0.5]
    end

    test "respects :rotations — single-rotation list" do
      terms = Enum.map(1..5, fn i -> term("t#{i}", 1.0 - i / 10) end)
      placements = Layout.layout(terms, rotations: [90])

      assert Enum.all?(placements, &(&1.rotation == 90))
    end

    test "rotation choice is deterministic across runs" do
      terms = Enum.map(1..10, fn i -> term("term#{i}", 1.0 - i / 20) end)

      r1 = Layout.layout(terms, rotations: [0, 45, 90])
      r2 = Layout.layout(terms, rotations: [0, 45, 90])

      assert r1 == r2
    end

    test "custom :font_metrics callback is honoured" do
      called = self()

      metrics_fun = fn term_text, font_size ->
        send(called, {:metrics_called, term_text, font_size})
        {String.length(term_text) * font_size, font_size}
      end

      [p] = Layout.layout([term("hello", 1.0)], font_metrics: metrics_fun)

      assert_received {:metrics_called, "hello", _}
      assert p.width == 5 * p.font_size
    end

    test "placements include all required fields" do
      [p] = Layout.layout([term("hello", 1.0)])

      keys = Map.keys(p)

      assert :term in keys
      assert :weight in keys
      assert :count in keys
      assert :kind in keys
      assert :x in keys
      assert :y in keys
      assert :width in keys
      assert :height in keys
      assert :font_size in keys
      assert :rotation in keys
    end

    test "empty input returns []" do
      assert Layout.layout([]) == []
    end
  end

  describe "integration with Text.WordCloud.terms/2" do
    test "round-trips a real cloud through the layout" do
      text = """
      Machine learning is a subset of artificial intelligence. Machine
      learning algorithms build a model based on sample data.
      """

      terms = Text.WordCloud.terms(text, language: :en, max_terms: 10)
      placements = Layout.layout(terms, width: 800, height: 600)

      # At least most of the terms should fit on a generous canvas.
      assert length(placements) >= div(length(terms), 2)

      # All placements must lie within the canvas bounds.
      Enum.each(placements, fn p ->
        assert p.x - p.width / 2 >= 0
        assert p.x + p.width / 2 <= 800
        assert p.y - p.height / 2 >= 0
        assert p.y + p.height / 2 <= 600
      end)
    end
  end

  defp boxes_overlap?({l1, t1, r1, b1}, {l2, t2, r2, b2}) do
    not (r1 <= l2 or r2 <= l1 or b1 <= t2 or b2 <= t1)
  end
end
