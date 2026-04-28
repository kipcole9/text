defmodule Text.WordCloud.Layout do
  @moduledoc """
  Wordle-style spiral layout for word-cloud rendering.

  Takes a list of weighted terms (the output of `Text.WordCloud.terms/2`)
  and produces a list of placements — `(x, y, width, height, font_size,
  rotation)` tuples — that can be handed to any rendering surface (SVG,
  Canvas, PDF, …). The layout itself is renderer-agnostic: this module
  produces no markup.

  ### Algorithm

  Higher-weight terms are placed first, starting at the canvas centre.
  Each subsequent term sweeps outward along an Archimedean spiral; at
  each sample point, the candidate bounding box is tested against
  every previously-placed box. The first non-colliding position wins.
  Terms that find no fit within the canvas bounds are dropped from
  the output.

  This is the same recipe Jonathan Feinberg used in the original
  Wordle implementation (and that d3-cloud follows in the browser).
  Pure-BEAM bounding-box collision detection scales fine for the
  typical 100–300-term clouds; for larger inputs an occupancy-grid
  refinement would be the natural follow-up.

  ### Font metrics

  Word width and height depend on the rendering font. We can't measure
  that from inside Elixir without a font-rendering library, so the
  default metric callback uses a coarse monospace approximation
  (character width ≈ 0.6 × font size; height ≈ 1.2 × font size). For
  pixel-accurate layout, pass a `:font_metrics` callback that consults
  your real font (e.g. via Cairo, FreeType, or the browser's Canvas
  TextMetrics API in the consumer's runtime).

  """

  @typedoc "A placement map ready for rendering."
  @type placement :: %{
          term: String.t(),
          weight: float(),
          count: pos_integer(),
          kind: :word | :phrase,
          x: float(),
          y: float(),
          width: float(),
          height: float(),
          font_size: float(),
          rotation: number()
        }

  @typedoc "Term entries as returned by `Text.WordCloud.terms/2`."
  @type term_entry :: %{
          required(:term) => String.t(),
          required(:weight) => float(),
          required(:count) => pos_integer(),
          required(:kind) => :word | :phrase,
          optional(any()) => any()
        }

  @typedoc "Width/height pixel metrics for a term at a given font size."
  @type metrics :: {width :: number(), height :: number()}

  @doc """
  Lays out a list of weighted terms onto a `width × height` canvas.

  ### Arguments

  * `terms` — the output of `Text.WordCloud.terms/2` (or any list of
    `%{term, weight, count, kind}` maps).

  ### Options

  * `:width` — canvas width in pixels. Default `800`.

  * `:height` — canvas height in pixels. Default `600`.

  * `:font_size_range` — `{min, max}` font size, in pixels. The top
    weight (`1.0`) maps to the max; weight `0.0` maps to the min.
    Default `{12, 96}`.

  * `:rotations` — list of rotation angles (degrees) to choose from
    per term. Default `[0]` (horizontal only). Common alternatives
    are `[0, 90]` or `[-30, 0, 30]`.

  * `:padding` — pixel padding added to every bounding box for
    collision testing. Default `2`.

  * `:font_metrics` — `(term, font_size) -> {width, height}`
    callback. Default uses a monospace approximation (character
    width = `0.6 × font_size`, height = `1.2 × font_size`).

  * `:spiral_step` — angular increment of the Archimedean spiral
    sampling. Smaller = more thorough but slower. Default `0.1`.

  * `:max_spiral_radius` — cap on spiral radius (pixels) before
    declaring "no fit". Default `max(width, height)`.

  ### Returns

  * A list of placement maps with `x`, `y`, `width`, `height`,
    `font_size`, and `rotation` filled in. Sorted in placement order
    (highest weight first). Terms that did not fit are omitted.

  ### Examples

      iex> terms = [%{term: "hello", weight: 1.0, count: 5, kind: :word}]
      iex> [p] = Text.WordCloud.Layout.layout(terms, width: 800, height: 600)
      iex> p.term
      "hello"
      iex> p.font_size > 0
      true

  """
  @spec layout([term_entry()], keyword()) :: [placement()]
  def layout(terms, options \\ []) do
    width = Keyword.get(options, :width, 800)
    height = Keyword.get(options, :height, 600)
    {min_fs, max_fs} = Keyword.get(options, :font_size_range, {12, 96})
    rotations = Keyword.get(options, :rotations, [0])
    padding = Keyword.get(options, :padding, 2)
    metrics = Keyword.get(options, :font_metrics, &default_metrics/2)
    spiral_step = Keyword.get(options, :spiral_step, 0.1)
    max_radius = Keyword.get(options, :max_spiral_radius, max(width, height))

    centre_x = width / 2
    centre_y = height / 2

    sorted = Enum.sort_by(terms, &(-&1.weight))

    {placed, _boxes} =
      Enum.reduce(sorted, {[], []}, fn term, {placed_acc, boxes_acc} ->
        font_size = font_size_for(term.weight, min_fs, max_fs)
        rotation = pick_rotation(term, rotations)
        {raw_w, raw_h} = metrics.(term.term, font_size)
        {bw, bh} = rotated_box(raw_w, raw_h, rotation)

        case find_position(
               bw + padding,
               bh + padding,
               boxes_acc,
               centre_x,
               centre_y,
               width,
               height,
               spiral_step,
               max_radius
             ) do
          {:ok, x, y} ->
            placement = %{
              term: term.term,
              weight: term.weight,
              count: term.count,
              kind: term.kind,
              x: x,
              y: y,
              width: raw_w,
              height: raw_h,
              font_size: font_size,
              rotation: rotation
            }

            box = {x - (bw + padding) / 2, y - (bh + padding) / 2, bw + padding, bh + padding}
            {[placement | placed_acc], [box | boxes_acc]}

          :no_fit ->
            {placed_acc, boxes_acc}
        end
      end)

    Enum.reverse(placed)
  end

  # ---- font sizing -----------------------------------------------------

  defp font_size_for(weight, min_fs, max_fs) when weight >= 0.0 and weight <= 1.0 do
    min_fs + weight * (max_fs - min_fs)
  end

  # Deterministically pick a rotation: hash the term so repeated layouts
  # produce identical output. Avoids the seeded-randomness footgun.
  defp pick_rotation(_term, [single]), do: single

  defp pick_rotation(%{term: term}, rotations) do
    index = :erlang.phash2(term, length(rotations))
    Enum.at(rotations, index)
  end

  # ---- bounding box rotation -------------------------------------------

  # For axis-aligned collision testing, a rotated box is approximated by
  # its axis-aligned bounding box (AABB). For the common 0/±90/±30 cases
  # this is conservative but produces visually-pleasing layouts.
  defp rotated_box(w, h, 0), do: {w, h}
  defp rotated_box(w, h, 180), do: {w, h}
  defp rotated_box(w, h, 90), do: {h, w}
  defp rotated_box(w, h, -90), do: {h, w}
  defp rotated_box(w, h, 270), do: {h, w}

  defp rotated_box(w, h, degrees) do
    rad = degrees * :math.pi() / 180.0
    abs_cos = abs(:math.cos(rad))
    abs_sin = abs(:math.sin(rad))
    {w * abs_cos + h * abs_sin, w * abs_sin + h * abs_cos}
  end

  # ---- spiral search ---------------------------------------------------

  # Samples points along an Archimedean spiral r = a*θ, with `a` chosen
  # so the spiral expands at roughly 1 pixel per radian — fine-grained
  # enough that the search rarely overshoots a feasible placement.
  defp find_position(box_w, box_h, boxes, cx, cy, canvas_w, canvas_h, step, max_radius) do
    do_spiral(0.0, box_w, box_h, boxes, cx, cy, canvas_w, canvas_h, step, max_radius)
  end

  defp do_spiral(theta, _bw, _bh, _boxes, _cx, _cy, _cw, _ch, _step, max_r) when theta > max_r do
    :no_fit
  end

  defp do_spiral(theta, bw, bh, boxes, cx, cy, canvas_w, canvas_h, step, max_radius) do
    r = theta
    x = cx + r * :math.cos(theta)
    y = cy + r * :math.sin(theta)

    if within_canvas?(x, y, bw, bh, canvas_w, canvas_h) and not collides?(x, y, bw, bh, boxes) do
      {:ok, x, y}
    else
      do_spiral(theta + step, bw, bh, boxes, cx, cy, canvas_w, canvas_h, step, max_radius)
    end
  end

  defp within_canvas?(x, y, bw, bh, canvas_w, canvas_h) do
    x - bw / 2 >= 0 and x + bw / 2 <= canvas_w and
      y - bh / 2 >= 0 and y + bh / 2 <= canvas_h
  end

  # AABB intersection test: two boxes overlap iff each axis interval
  # overlaps. The `boxes` list stores `{top_left_x, top_left_y, w, h}`
  # tuples; the candidate `(x, y)` is its centre.
  defp collides?(x, y, bw, bh, boxes) do
    candidate_left = x - bw / 2
    candidate_right = x + bw / 2
    candidate_top = y - bh / 2
    candidate_bottom = y + bh / 2

    Enum.any?(boxes, fn {bx, by, ew, eh} ->
      not (candidate_right < bx or candidate_left > bx + ew or
             candidate_bottom < by or candidate_top > by + eh)
    end)
  end

  # ---- font metrics: monospace approximation --------------------------

  defp default_metrics(term, font_size) do
    char_width = font_size * 0.6
    char_height = font_size * 1.2
    width = String.length(term) * char_width
    {width, char_height}
  end
end
