# Keyword-in-context (KWIC) concordance

`Text.KWIC` finds every occurrence of a term in a text and returns each match with its surrounding context — the classic linguistic concordance view that lets you see at a glance *how* a word is used across a document, not just *whether* it appears.

This is the tool to reach for when you've found that some word matters (via `Text.WordCloud`, a frequency count, or a search hit) and you now want to actually look at every place it shows up. A frequency cloud tells you `Earth` appears six times in the corpus; a concordance tells you the Earth gets demolished, that it was mostly harmless, that the dolphins knew it was coming, and that Trillian is from there.

## Quick start

```elixir
text = """
The Earth was demolished to make way for a hyperspace bypass.
Trillian, formerly known as Tricia McMillan of Earth, is a brilliant
astrophysicist. The mice ran an experiment on the Earth. The dolphins
left Earth knowing what was coming. Mostly harmless: that's what the
revised Guide entry on Earth said.
"""

Text.KWIC.concordance(text, "Earth", context: 4)
#=> [
#=>   %Text.KWIC.Match{
#=>     position: 1,
#=>     left: ["The"],
#=>     term: "Earth",
#=>     right: ["was", "demolished", "to", "make"]
#=>   },
#=>   %Text.KWIC.Match{
#=>     position: 14,
#=>     left: ["as", "Tricia", "McMillan", "of"],
#=>     term: "Earth",
#=>     right: ["is", "a", "brilliant", "astrophysicist"]
#=>   },
#=>   ...
#=> ]
```

Each `Text.KWIC.Match` carries the full context: the matched token in its original casing, the tokens to its left and right, and its position in the document.

To pretty-print:

```elixir
text
|> Text.KWIC.concordance("Earth", context: 4)
|> Enum.map(&Text.KWIC.format(&1, width: 30))
|> Enum.each(&IO.puts/1)

#=>                            The | Earth | was demolished to make
#=>          as Tricia McMillan of | Earth | is a brilliant astrophysicist
#=>     mice ran an experiment on | Earth | The dolphins left Earth knowing
#=>            The dolphins left | Earth | knowing what was coming
#=>     the revised Guide entry on | Earth | said
```

The `:width` option pads the left context to a fixed width so the term column aligns cleanly across rows — the standard concordance presentation. Suddenly the *uses* of "Earth" pop out: it's an object of demolition, a place of origin, a subject of experiments, a thing-being-left, and a Guide entry.

## Match struct

```elixir
%Text.KWIC.Match{
  position: 1,           # zero-based token index in the input
  left: ["The"],         # tokens preceding the match
  term: "Earth",         # the matched token, in its ORIGINAL casing
  right: ["was", "demolished", "to", "make"]
}
```

* **`:position`** is useful for sorting, deduplicating, or correlating matches across different searches. It's the index in the tokenizer's output, not the byte offset — convert to a byte offset only if you also store the original input and re-tokenize.

* **`:term` preserves original case** even when the search itself is case-insensitive. So a search for `"earth"` returns `Earth` / `earth` / `EARTH` matches with each surface form intact in the result.

## Context width

The `:context` option controls how many tokens of left/right context come back. Default `5`. Choose a value that fits your screen and your purpose:

```elixir
Text.KWIC.concordance(text, "towel", context: 3)
# Tight, easy to scan in a list:
#=> [%Match{left: ["was", "given", "a"], term: "towel", right: ["—", "about", "the"]}]

Text.KWIC.concordance(text, "towel", context: 12)
# Wider, gives the full sentence-level context:
#=> [%Match{left: [..., "Arthur", "was", "given", "a"], term: "towel", right: [...]}]
```

Two common rules of thumb:

* **For display** (concordance lines printed to a terminal or web view): match the context to your row width. ~5–8 tokens fits comfortably on an 80-column terminal at default sizes.

* **For collocation analysis** (programmatic — looking at what words consistently appear *near* the target): use a wider window like 10–20 to capture full-sentence relationships, then aggregate.

## Case sensitivity

Searches are case-insensitive by default — `"earth"` matches `Earth` and `earth` both. Pass `case_sensitive: true` to require an exact match:

```elixir
Text.KWIC.concordance(text, "Earth", case_sensitive: true)
# Only the original-casing "Earth" tokens.

Text.KWIC.concordance(text, "earth", case_sensitive: true)
# Empty if the corpus only uses "Earth" (capitalised).
```

For literary or scholarly use case-sensitive search is sometimes important: distinguishing `God` from `god`, `Paris` (the place) from `paris` (the dispute), `Plant` from `plant`. For most engineering-style "find all uses" workflows, the case-insensitive default is what you want.

## Custom tokenizers

`concordance/3` defaults to `Text.Segment.words/1` — Unicode UAX #29 word segmentation, locale-naive, punctuation-stripped. That's right for most text. Override with `:tokenizer` if you need different splitting:

```elixir
# Keep punctuation as separate tokens (useful for code, structured text):
Text.KWIC.concordance(text, "earth",
  tokenizer: &Text.Segment.words(&1, punctuation: :keep)
)

# Locale-aware word breaks (CJK, Thai, etc.):
Text.KWIC.concordance(thai_text, "ประเทศ",
  tokenizer: &Text.Segment.words(&1, locale: "th")
)

# Custom tokenization (e.g. character-level for languages without word breaks):
Text.KWIC.concordance(text, "侃",
  tokenizer: &String.graphemes/1
)
```

The tokenizer is a single-arity function `String.t() -> [String.t()]`. Whatever it returns is what KWIC searches against; the `:term` you pass is matched against tokens as-is (after case folding, if requested).

## Formatting

`Text.KWIC.format/2` converts a single `Match` to a printable string:

```elixir
match = hd(Text.KWIC.concordance(text, "demolished", context: 4))

Text.KWIC.format(match)
#=> "Earth was | demolished | to make way for a"

Text.KWIC.format(match, separator: " >>> ")
#=> "Earth was >>> demolished >>> to make way for a"

Text.KWIC.format(match, width: 25)
#=> "                Earth was | demolished | to make way for a"
```

The `:width` padding aligns the *right edge* of the left-context column. Pick a value at least as wide as your widest expected left-context to keep the term column fixed in position across rows — this is the visual cue that makes a concordance table actually scannable.

## Patterns

### Collocate scan

What words consistently appear near a target term?

```elixir
collocates =
  text
  |> Text.KWIC.concordance("Vogon", context: 5)
  |> Enum.flat_map(fn m -> m.left ++ m.right end)
  |> Enum.map(&String.downcase/1)
  |> Enum.frequencies()
  |> Enum.sort_by(fn {_w, n} -> -n end)
  |> Enum.take(10)
```

For larger corpora reach for `Text.Collocation.bigrams/2` instead — KWIC is meant for human-readable inspection of a handful of matches, not bulk co-occurrence statistics.

### Sense disambiguation

When a word has multiple senses, the contexts cluster:

```elixir
Text.KWIC.concordance(corpus, "fish", context: 6)
# Some matches will be about the babel fish (a creature);
# others about "thanks for all the fish" (the dolphins' farewell).
# Visually obvious in the concordance, hard to spot in a frequency view.
```

### Finding all forms

KWIC searches for an exact token. Inflected variants need separate calls or a stem-bucket pre-pass:

```elixir
~w[demolish demolished demolishing demolition]
|> Enum.flat_map(&Text.KWIC.concordance(text, &1, context: 4))
|> Enum.sort_by(& &1.position)
```

For a more general "all morphological variants" search, run `Text.WordCloud.terms/2` with `stem: true` to find the surface forms present in the corpus, then loop them through KWIC.

### Cross-document concordance

Each `concordance/3` call works on one input. To search across many documents, loop and tag the results:

```elixir
documents = %{
  "h2g2" => h2g2_text,
  "rest_at_eou" => rest_at_eou_text,
  "life_universe" => life_universe_text
}

documents
|> Enum.flat_map(fn {doc_id, text} ->
  text
  |> Text.KWIC.concordance("Vogon", context: 5)
  |> Enum.map(&{doc_id, &1})
end)
|> Enum.each(fn {doc_id, m} ->
  IO.puts("#{doc_id}\t#{Text.KWIC.format(m, width: 30)}")
end)
```

Adds a document column to the concordance — handy for tracing how a term's usage drifts across a series.

## Limitations

* **Single-token search only.** Multi-word phrases (`"hyperspace bypass"`) need a separate pass — tokenize the corpus, find positions where the phrase tokens align consecutively, and build the match manually. A future revision may add native phrase support; for now it's outside scope.

* **No regex / wildcard.** The term match is exact-equality against the (folded) token. For pattern matching, pre-process the corpus to extract the matching tokens, then concordance each one.

* **Whole-document tokenization.** `concordance/3` tokenizes the entire input on every call. For very large corpora that you'll be searching many times, pre-tokenize once and pass the token list directly via a custom `:tokenizer` that just returns the cached list:

  ```elixir
  cached_tokens = Text.Segment.words(huge_text)
  noop_tokenizer = fn _text -> cached_tokens end

  Text.KWIC.concordance(huge_text, "earth", tokenizer: noop_tokenizer)
  ```

* **Position is token-indexed, not byte-indexed.** Cross-reference with the original input requires re-tokenization or carrying a position-to-offset map alongside the matches.

## When to reach for KWIC

| Question | Tool |
|---|---|
| "Does this word appear in the document?" | `String.contains?/2` |
| "Where does this word appear?" | `String.split/2` then walk |
| "How frequently does this word appear?" | `Text.WordCloud.terms` with `:frequency` scoring |
| "What does this word mean *here* — how is it used?" | **`Text.KWIC.concordance`** |
| "What words are statistically associated with this one?" | `Text.Collocation.bigrams` |
| "Highlight every occurrence in a UI" | `Text.KWIC.concordance` + render `position` and `term` slices |

Concordances are a literary-scholarship and corpus-linguistics tool by lineage — but they're equally useful in any context where you've zeroed in on an interesting word and now need to look at the actual sentences it lives in. Don't panic.
