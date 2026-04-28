defmodule Text.WordCloud.SVGTest do
  use ExUnit.Case, async: true
  doctest Text.WordCloud.SVG

  alias Text.WordCloud.{Layout, SVG}

  defp placements_for(text) do
    text
    |> Text.WordCloud.terms(language: :en, max_terms: 8)
    |> Layout.layout(width: 600, height: 400)
  end

  describe "render/2 — basic structure" do
    test "produces a valid SVG with XML prolog and svg root" do
      svg =
        SVG.render(placements_for("alpha beta gamma alpha beta. alpha beta delta."),
          width: 600,
          height: 400
        )

      assert String.starts_with?(svg, "<?xml version=\"1.0\"")
      assert svg =~ ~s|<svg xmlns="http://www.w3.org/2000/svg"|
      assert svg =~ ~s|width="600"|
      assert svg =~ ~s|height="400"|
      assert svg =~ ~s|viewBox="0 0 600 400"|
      assert String.ends_with?(String.trim(svg), "</svg>")
    end

    test "renders one <text> element per placement" do
      placements = placements_for("alpha beta gamma alpha beta. alpha beta delta.")
      svg = SVG.render(placements)

      text_count =
        Regex.scan(~r|<text\b|, svg) |> length()

      assert text_count == length(placements)
    end

    test "renders no background by default" do
      svg = SVG.render(placements_for("alpha beta gamma alpha beta. alpha beta delta."))
      refute svg =~ "<rect"
    end

    test "renders a background rect when :background is given" do
      svg =
        SVG.render(
          placements_for("alpha beta gamma alpha beta. alpha beta delta."),
          background: "#fafafa"
        )

      assert svg =~ ~s|<rect|
      assert svg =~ ~s|fill="#fafafa"|
    end

    test "empty placement list produces a valid empty SVG" do
      svg = SVG.render([], width: 100, height: 50)

      assert svg =~ ~s|<svg|
      assert svg =~ ~s|</svg>|
      refute svg =~ ~s|<text|
    end
  end

  describe "render/2 — XML escaping" do
    test "term content is XML-escaped" do
      placement = %{
        term: ~s|<script>alert('x')</script>|,
        weight: 1.0,
        count: 1,
        kind: :word,
        x: 100.0,
        y: 50.0,
        width: 80.0,
        height: 24.0,
        font_size: 24.0,
        rotation: 0
      }

      svg = SVG.render([placement])

      refute svg =~ "<script>alert"
      assert svg =~ "&lt;script&gt;"
      assert svg =~ "&apos;"
    end
  end

  describe "render/2 — single-colour fallback" do
    test "uses :fill when no palette is given" do
      svg =
        SVG.render(placements_for("alpha beta gamma alpha beta. alpha beta delta."),
          fill: "#ff00ff"
        )

      assert svg =~ ~s|fill="#ff00ff"|
    end
  end

  describe "render/2 — palette as list of hex strings" do
    test "by_index strategy round-robins through the palette" do
      placements = placements_for("alpha beta gamma alpha beta. alpha beta delta.")

      svg =
        SVG.render(placements,
          palette: ["#ff0000", "#00ff00", "#0000ff"],
          color_strategy: :by_index
        )

      assert svg =~ ~s|fill="#ff0000"|
      assert svg =~ ~s|fill="#00ff00"|
    end

    test "by_weight strategy assigns first colour to top-weighted term" do
      placements = placements_for("alpha beta gamma alpha beta. alpha beta delta.")

      svg =
        SVG.render(placements,
          palette: ["#aa0000", "#00aa00", "#0000aa"],
          color_strategy: :by_weight
        )

      # Top weight should appear first in placement order; its fill
      # should be the first palette colour.
      [first_fill] = Regex.run(~r|fill="(#[0-9a-f]{6})"|, svg, capture: :all_but_first)
      assert first_fill == "#aa0000"
    end

    test "by_hash strategy is deterministic across runs" do
      placements = placements_for("alpha beta gamma alpha beta. alpha beta delta.")

      svg1 = SVG.render(placements, palette: ["#aaa", "#bbb", "#ccc"], color_strategy: :by_hash)
      svg2 = SVG.render(placements, palette: ["#aaa", "#bbb", "#ccc"], color_strategy: :by_hash)

      assert svg1 == svg2
    end
  end

  if Code.ensure_loaded?(Color) do
    describe "render/2 — Color.Palette.Tonal palette" do
      test "uses every stop in descending direction by default" do
        placements = placements_for("alpha beta gamma alpha beta gamma delta epsilon zeta.")

        palette = Color.Palette.tonal("#3b82f6", name: "blue")
        svg = SVG.render(placements, palette: palette)

        # The darkest stop (highest label) should appear in the SVG.
        darkest = palette.stops |> Enum.max_by(fn {label, _c} -> label end) |> elem(1)
        darkest_hex = Color.to_hex(darkest)
        assert svg =~ ~s|fill="#{darkest_hex}"|
      end

      test "ascending direction maps top weight to lightest stop" do
        placements = placements_for("alpha beta gamma alpha beta gamma.")

        palette = Color.Palette.tonal("#3b82f6", name: "blue")

        svg =
          SVG.render(placements, palette: palette, palette_direction: :ascending)

        lightest = palette.stops |> Enum.min_by(fn {label, _c} -> label end) |> elem(1)
        lightest_hex = Color.to_hex(lightest)

        # Top-weighted term (first in placement order) gets the lightest stop.
        [first_fill] = Regex.run(~r|fill="(#[0-9a-f]+)"|, svg, capture: :all_but_first)
        assert first_fill == lightest_hex
      end
    end

    test "non-hex colour input is normalised via Color.to_hex/1" do
      placements = placements_for("alpha beta gamma alpha beta.")

      svg = SVG.render(placements, fill: "rebeccapurple")

      assert svg =~ ~s|fill="#663399"|
    end
  end

  describe "render/2 — invalid input" do
    test "raises on a non-list, non-Color.Palette palette" do
      placements = placements_for("alpha beta gamma alpha beta.")

      assert_raise ArgumentError, ~r/expected :palette/, fn ->
        SVG.render(placements, palette: 42)
      end
    end
  end
end
