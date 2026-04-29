# Generates the example SVGs embedded in `guides/word_clouds.md`.
#
# Run from the project root:
#
#     mix run priv/scripts/gen_word_cloud_examples.exs
#
# The corpus is a tribute paragraph stitched together from short
# fair-use HHGTTG phrases plus connecting prose. Recurring entities
# (Earth, Vogon, Arthur, towel, babel fish, Heart of Gold, ...) give
# the different scoring algorithms enough overlap and divergence to
# be visibly distinct.

corpus = """
The Hitchhiker's Guide to the Galaxy is a wholly remarkable book.
It has been compiled and recompiled many times over many years and
under many different editorships, and it contains contributions from
countless numbers of travellers and researchers across the galaxy.

Don't panic. The answer to the ultimate question of life, the universe,
and everything is forty-two — though the question itself was lost when
the Earth was demolished to make way for a hyperspace bypass. Time is
an illusion. Lunchtime, doubly so.

Arthur Dent had had a fairly bad day. His house was about to be
demolished to make way for a bypass, the Earth was about to be
demolished to make way for a hyperspace bypass, and his best friend
Ford Prefect turned out to be from a small planet somewhere in the
vicinity of Betelgeuse, not Guildford as previously claimed. Arthur
was given a towel — about the most massively useful thing an interstellar
hitchhiker can have — and dragged onto a Vogon constructor ship.

Vogons are not actually evil. They are bad-tempered, bureaucratic,
officious, and callous. They write some of the third-worst poetry in
the universe. The Vogons would not lift a finger to save their own
grandmothers from the Ravenous Bugblatter Beast of Traal without an
order signed in triplicate, sent in, sent back, queried, lost, found,
subjected to public inquiry, lost again, and finally buried in soft
peat for three months and recycled as firelighters.

The babel fish is small, yellow, leech-like, and probably the oddest
thing in the universe. It feeds on brainwave energy and excretes a
telepathic matrix that lets the wearer instantly understand any
language. The Improbability Drive of the starship Heart of Gold renders
the impossible possible by harnessing the very fabric of improbability
itself; Zaphod Beeblebrox, the two-headed, three-armed President of
the Galaxy, stole it on the day of its unveiling.

Marvin the Paranoid Android has a brain the size of a planet and is
asked to do menial tasks. Trillian, formerly known as Tricia McMillan
of Earth, is a brilliant astrophysicist. Slartibartfast designed the
fjords of Norway and won an award for the crinkly bits along the
edges. The Restaurant at the End of the Universe serves dinner with a
view of existence collapsing in on itself. The Total Perspective
Vortex is the worst torture in the galaxy: it shows you exactly how
insignificant you are.

The mice, it turns out, are pan-dimensional hyperintelligent beings
running an experiment on the Earth. The dolphins, knowing in advance
that the Earth was about to be demolished, left with a parting message:
so long, and thanks for all the fish.
"""

assets_dir = Path.join([File.cwd!(), "guides", "word_clouds_assets"])
File.mkdir_p!(assets_dir)

# Common dimensions for square examples (palette/strategy/rotation
# illustrations) and wider ones for the readable scoring/ngram views.
square = [width: 800, height: 800]
wide = [width: 1000, height: 600]

# Default font stack for every example.
font_family = "Helvetica Neue, Arial, sans-serif"

# Single source of truth for term extraction so every example uses
# the same candidate set (we vary scoring/layout/colour, not the
# corpus or stopwords).
defaults = [language: :en, max_terms: 50]

write = fn name, svg ->
  path = Path.join(assets_dir, name <> ".svg")
  File.write!(path, svg)
  IO.puts("→ #{Path.relative_to_cwd(path)}  (#{byte_size(svg)} B)")
end

render_simple = fn placements, opts ->
  Text.WordCloud.SVG.render(
    placements,
    Keyword.merge([font_family: font_family, background: "#fafafa"], opts)
  )
end

# ---- 1. baseline (default everything) ---------------------------------

baseline_terms = Text.WordCloud.terms(corpus, defaults)
baseline_placements = Text.WordCloud.Layout.layout(baseline_terms, wide)
write.("basic", render_simple.(baseline_placements, wide))

# ---- 2. scoring backends ----------------------------------------------

for scoring <- [:frequency, :rake, :text_rank] do
  terms = Text.WordCloud.terms(corpus, [{:scoring, scoring} | defaults])

  # TextRank's top phrases are 3-grams that occupy a lot of horizontal
  # space at full font size; cap the max so more candidates fit.
  layout_opts =
    case scoring do
      :text_rank -> [{:font_size_range, {12, 48}} | wide]
      _ -> wide
    end

  placements = Text.WordCloud.Layout.layout(terms, layout_opts)
  write.("scoring_#{scoring}", render_simple.(placements, wide))
end

# ---- 3. n-gram range --------------------------------------------------

unigrams = Text.WordCloud.terms(corpus, [{:ngram_range, {1, 1}} | defaults])
phrases = Text.WordCloud.terms(corpus, [{:ngram_range, {2, 3}}, {:min_count, 1} | defaults])

write.("ngrams_unigrams", render_simple.(Text.WordCloud.Layout.layout(unigrams, wide), wide))
write.("ngrams_phrases", render_simple.(Text.WordCloud.Layout.layout(phrases, wide), wide))

# ---- 4. stopword filtering --------------------------------------------

with_stopwords = baseline_terms

without_stopwords =
  Text.WordCloud.terms(corpus, [{:stopwords, :none}, {:scoring, :frequency} | defaults])

write.("stopwords_on", render_simple.(Text.WordCloud.Layout.layout(with_stopwords, wide), wide))

write.(
  "stopwords_off",
  render_simple.(Text.WordCloud.Layout.layout(without_stopwords, wide), wide)
)

# ---- 5. rotations -----------------------------------------------------

rotation_terms = Text.WordCloud.terms(corpus, defaults)

write.(
  "rotations_horizontal",
  render_simple.(Text.WordCloud.Layout.layout(rotation_terms, square), square)
)

write.(
  "rotations_mixed",
  render_simple.(
    Text.WordCloud.Layout.layout(
      rotation_terms,
      [{:rotations, [-30, 0, 30]} | square]
    ),
    square
  )
)

write.(
  "rotations_radial",
  render_simple.(
    Text.WordCloud.Layout.layout(rotation_terms, [{:rotations, :radial} | square]),
    square
  )
)

write.(
  "rotations_spiral",
  render_simple.(
    Text.WordCloud.Layout.layout(rotation_terms, [{:rotations, :spiral} | square]),
    square
  )
)

# ---- 6. palettes ------------------------------------------------------

palette_terms = Text.WordCloud.terms(corpus, defaults)
palette_placements = Text.WordCloud.Layout.layout(palette_terms, square)

# 6a. single fill colour
write.(
  "palette_single",
  render_simple.(palette_placements, [{:fill, "#1f2937"} | square])
)

# 6b. list of brand colours
brand_palette = ["#2563eb", "#dc2626", "#16a34a", "#9333ea", "#ea580c", "#0891b2"]

write.(
  "palette_list",
  render_simple.(palette_placements, [
    {:palette, brand_palette},
    {:color_strategy, :by_index} | square
  ])
)

# 6c. tonal scale (cool blue)
tonal_blue = Color.Palette.tonal("#3b82f6", name: "blue")

write.(
  "palette_tonal_blue",
  render_simple.(palette_placements, [{:palette, tonal_blue} | square])
)

# 6d. tonal scale (warm)
tonal_warm = Color.Palette.tonal("#dc2626", name: "warm")

write.(
  "palette_tonal_warm",
  render_simple.(palette_placements, [{:palette, tonal_warm} | square])
)

# ---- 7. colour strategies (same palette, three behaviours) ------------

# Use a 5-colour palette so the differences are obvious.
strategy_palette = ["#1f2937", "#2563eb", "#16a34a", "#dc2626", "#9333ea"]

for strategy <- [:by_weight, :by_index, :by_hash] do
  write.(
    "strategy_#{strategy}",
    render_simple.(palette_placements, [
      {:palette, strategy_palette},
      {:color_strategy, strategy} | square
    ])
  )
end

# ---- 8. stemming ------------------------------------------------------

# Use a corpus with deliberate inflectional variation so the
# bucketing effect is obvious. The HHGTTG corpus has a
# `demolish/demolished/demolishing` cluster that consolidates
# nicely under stemming.
stem_terms_off = Text.WordCloud.terms(corpus, [{:scoring, :frequency} | defaults])

stem_terms_on =
  Text.WordCloud.terms(corpus, [{:scoring, :frequency}, {:stem, true} | defaults])

write.(
  "stemming_off",
  render_simple.(Text.WordCloud.Layout.layout(stem_terms_off, wide), wide)
)

write.(
  "stemming_on",
  render_simple.(Text.WordCloud.Layout.layout(stem_terms_on, wide), wide)
)

# ---- 9. complete showcase ---------------------------------------------

showcase_terms = Text.WordCloud.terms(corpus, [{:max_terms, 60} | defaults])

showcase_placements =
  Text.WordCloud.Layout.layout(
    showcase_terms,
    width: 1000,
    height: 1000,
    rotations: :radial,
    font_size_range: {12, 80},
    padding: 4
  )

write.(
  "showcase",
  Text.WordCloud.SVG.render(
    showcase_placements,
    width: 1000,
    height: 1000,
    palette: tonal_blue,
    background: "#fafafa",
    font_family: font_family
  )
)

IO.puts("\nDone.")
