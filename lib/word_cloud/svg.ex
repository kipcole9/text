defmodule Text.WordCloud.SVG do
  @moduledoc """
  Renders a laid-out word cloud as an SVG string.

  Takes the output of `Text.WordCloud.Layout.layout/2` and produces a
  self-contained SVG document. The result is a string suitable for
  writing to a `.svg` file, embedding inline in HTML, or piping to a
  rasteriser for PNG/PDF export. No DOM, no NIFs, no runtime
  dependencies — just text concatenation.

  ### Colour palettes

  Per-word colour comes from a pluggable `:palette` option:

  * **A list of colour inputs** — hex strings, CSS named colours, or
    anything `Color.new/1` accepts (when the optional `:color`
    dependency is present). Without `:color`, only hex strings (`"#rrggbb"`
    or `"#rgb"`) are accepted directly.

  * **A `Color.Palette.Tonal` struct** — uses its stops as the
    palette. Higher-weight terms map to darker (or lighter, configurable)
    stops.

  * **A `Color.Palette.Theme` struct** — uses the theme's `:primary`
    scale; same mapping rules as `:tonal`.

  * **`nil`** *(default)* — every term renders in a single fill colour
    (`:fill` option, default `"#1f2937"`).

  ### Mapping strategy

  The `:color_strategy` option controls how each term picks a colour
  from the palette:

  * `:by_weight` *(default)* — terms are sorted by weight descending
    and mapped onto the palette stops in order. The top-weighted term
    gets the first palette colour. With a tonal scale you typically
    want `:by_weight, palette_direction: :descending` so the highest-
    weighted term gets the *darkest* stop.

  * `:by_index` — round-robin through the palette in placement order.

  * `:by_hash` — `:erlang.phash2(term, palette_size)` so identical
    terms always pick the same colour across runs.

  ### Background

  By default the SVG has no background. Pass `:background` (any colour
  input) to render a `<rect>` filling the canvas before the words.

  ### Fonts

  SVG itself doesn't embed font files; the rendered file references
  `:font_family` (default `"sans-serif"`). For a self-contained PDF or
  PNG you'll typically want to pass a specific webfont stack and pair
  it with a `:font_metrics` callback in the layout step that consults
  metrics for that exact font.

  """

  @type placement :: Text.WordCloud.Layout.placement()
  @type color_input :: String.t() | struct() | atom() | tuple()

  @typedoc """
  How term weights map onto palette colours.
  """
  @type strategy :: :by_weight | :by_index | :by_hash

  @typedoc """
  Direction of the palette traversal under `:by_weight`. `:ascending`
  walks the palette in its natural order (typically light → dark);
  `:descending` reverses it (dark → light), the more common choice for
  reading clouds where higher-weighted = "darker".
  """
  @type palette_direction :: :ascending | :descending

  @doc """
  Renders `placements` as an SVG string.

  ### Arguments

  * `placements` is a list of placement maps as returned by
    `Text.WordCloud.Layout.layout/2`.

  ### Options

  * `:width` — canvas width in pixels. Default `800`.

  * `:height` — canvas height in pixels. Default `600`.

  * `:palette` — colour source: a list of colour inputs, a
    `Color.Palette.Tonal` struct, a `Color.Palette.Theme` struct, or
    `nil` (single-colour rendering). Default `nil`.

  * `:color_strategy` — mapping strategy. One of `:by_weight`,
    `:by_index`, `:by_hash`. Default `:by_weight`.

  * `:palette_direction` — only used with `:by_weight` and a
    `Color.Palette.Tonal`/`Theme`. `:descending` (default) maps the
    top weight to the darkest stop; `:ascending` maps it to the
    lightest.

  * `:fill` — fallback fill colour for terms when no palette is given,
    or for terms that don't get a palette colour. Default `"#1f2937"`.

  * `:background` — colour input for a full-canvas `<rect>` background,
    or `nil` for transparent. Default `nil`.

  * `:font_family` — CSS font-family stack. Default `"sans-serif"`.

  * `:font_weight` — CSS font-weight value. Default `"600"`.

  ### Returns

  * An SVG document as a binary string. The result starts with
    `<?xml version="1.0" encoding="UTF-8"?>` and is safe to write
    directly to a `.svg` file.

  ### Examples

      iex> placements = [
      ...>   %{term: "hello", weight: 1.0, count: 5, kind: :word,
      ...>     x: 200.0, y: 100.0, width: 60.0, height: 24.0,
      ...>     font_size: 24.0, rotation: 0}
      ...> ]
      iex> svg = Text.WordCloud.SVG.render(placements, width: 400, height: 200)
      iex> svg =~ "<svg"
      true
      iex> svg =~ "hello"
      true

  """
  @spec render([placement()], keyword()) :: String.t()
  def render(placements, options \\ []) do
    width = Keyword.get(options, :width, 800)
    height = Keyword.get(options, :height, 600)
    palette = Keyword.get(options, :palette)
    strategy = Keyword.get(options, :color_strategy, :by_weight)
    direction = Keyword.get(options, :palette_direction, :descending)
    default_fill = Keyword.get(options, :fill, "#1f2937")
    background = Keyword.get(options, :background)
    font_family = Keyword.get(options, :font_family, "sans-serif")
    font_weight = Keyword.get(options, :font_weight, "600")

    palette_colors = resolve_palette(palette, direction)
    coloured = assign_colors(placements, palette_colors, strategy, normalise_color(default_fill))

    body =
      [
        background_rect(background, width, height),
        Enum.map(coloured, &render_text(&1, font_family, font_weight))
      ]
      |> :erlang.iolist_to_binary()

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
    #{body}</svg>
    """
  end

  # ---- palette resolution ---------------------------------------------

  defp resolve_palette(nil, _direction), do: []

  defp resolve_palette(list, _direction) when is_list(list) do
    Enum.map(list, &normalise_color/1)
  end

  defp resolve_palette(%{__struct__: module, stops: stops}, direction)
       when is_map(stops) do
    if tonal_struct?(module) do
      stops_to_colors(stops, direction)
    else
      raise ArgumentError, "unsupported palette struct: #{inspect(module)}"
    end
  end

  defp resolve_palette(%{__struct__: module} = theme, direction) do
    cond do
      theme_struct?(module) ->
        # Use the primary scale's stops.
        primary = Map.get(theme, :primary)

        if primary && Map.has_key?(primary, :stops) do
          stops_to_colors(primary.stops, direction)
        else
          raise ArgumentError,
                "Color.Palette.Theme is missing a :primary tonal scale: #{inspect(module)}"
        end

      true ->
        raise ArgumentError, "unsupported palette struct: #{inspect(module)}"
    end
  end

  defp resolve_palette(other, _direction) do
    raise ArgumentError,
          "expected :palette to be nil, a list, or a Color.Palette struct; got #{inspect(other)}"
  end

  defp tonal_struct?(module), do: module == Color.Palette.Tonal
  defp theme_struct?(module), do: module == Color.Palette.Theme

  # Tonal stops are typically `[50, 100, ..., 950]` — light to dark.
  # Sort numeric stops ascending; `:descending` reverses so the first
  # palette entry corresponds to the darkest stop.
  defp stops_to_colors(stops, direction) do
    sorted =
      stops
      |> Enum.sort_by(fn {label, _color} -> label end)
      |> Enum.map(fn {_label, color} -> normalise_color(color) end)

    case direction do
      :ascending -> sorted
      :descending -> Enum.reverse(sorted)
    end
  end

  # Convert any colour input to a `#rrggbb`/`#rrggbbaa` hex string.
  # Hex strings pass through unchanged — that's the only form we accept
  # without the optional `:color` dep.
  defp normalise_color("#" <> _ = hex), do: hex

  defp normalise_color(other) do
    if Code.ensure_loaded?(Color) do
      Color.to_hex(other)
    else
      raise ArgumentError,
            "non-hex colour #{inspect(other)} requires the optional :color dependency"
    end
  end

  # ---- per-term colour assignment -------------------------------------

  defp assign_colors(placements, [], _strategy, default_fill) do
    Enum.map(placements, fn p -> {p, default_fill} end)
  end

  defp assign_colors(placements, palette, :by_weight, _default_fill) do
    n = length(palette)

    placements
    |> Enum.with_index()
    |> Enum.sort_by(fn {p, _i} -> -p.weight end)
    |> Enum.with_index()
    |> Enum.map(fn {{p, original_index}, sorted_index} ->
      {p, original_index, Enum.at(palette, min(sorted_index, n - 1))}
    end)
    |> Enum.sort_by(fn {_p, original_index, _c} -> original_index end)
    |> Enum.map(fn {p, _i, color} -> {p, color} end)
  end

  defp assign_colors(placements, palette, :by_index, _default_fill) do
    n = length(palette)

    placements
    |> Enum.with_index()
    |> Enum.map(fn {p, i} -> {p, Enum.at(palette, rem(i, n))} end)
  end

  defp assign_colors(placements, palette, :by_hash, _default_fill) do
    n = length(palette)

    Enum.map(placements, fn p ->
      {p, Enum.at(palette, :erlang.phash2(p.term, n))}
    end)
  end

  # ---- SVG fragment generation ---------------------------------------

  defp background_rect(nil, _width, _height), do: ""

  defp background_rect(color, width, height) do
    fill = normalise_color(color)
    [~s|<rect width="#{width}" height="#{height}" fill="|, fill, ~s|"/>\n|]
  end

  defp render_text({placement, color}, font_family, font_weight) do
    %{term: term, x: x, y: y, font_size: font_size, rotation: rotation} = placement

    transform =
      if rotation == 0,
        do: "",
        else: ~s| transform="rotate(#{rotation} #{x} #{y})"|

    [
      ~s|<text x="|,
      to_string(x),
      ~s|" y="|,
      to_string(y),
      ~s|" font-size="|,
      to_string(font_size),
      ~s|" font-family="|,
      escape(font_family),
      ~s|" font-weight="|,
      to_string(font_weight),
      ~s|" fill="|,
      color,
      ~s|" text-anchor="middle" dominant-baseline="middle"|,
      transform,
      ~s|>|,
      escape(term),
      ~s|</text>\n|
    ]
  end

  # XML-escape five reserved characters. The colour and font-family
  # values come from controlled sources so we don't double-escape them
  # — but `term` is user content that may contain `<`, `>`, `&`.
  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
