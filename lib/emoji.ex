defmodule Text.Emoji do
  @moduledoc """
  Emoji detection and short-name conversion.

  Detection uses the Unicode `Extended_Pictographic` property, so it
  picks up the full emoji repertoire including newer additions
  without needing a per-release data update.

  Implementation note: the `Extended_Pictographic` regex is built at
  compile time from `Unicode.Emoji.emoji/0` rather than via PCRE2's
  `\\p{Extended_Pictographic}` syntax. Older PCRE2 versions bundled
  with OTP 26/27 do not always recognise the full property name, so
  expanding to an explicit codepoint character class keeps the
  library portable across OTP releases.

  Short-name conversion (`demojize/2`, `emojize/2`) uses a small
  bundled lookup of the most common emoji. It is not a complete
  CLDR annotation set; rare emoji round-trip as themselves. Users
  can extend the lookup at runtime via `add_emoji/1`.

  Sentiment scoring is provided by `sentiment/1` and
  `text_sentiment/1`, backed by the bundled Emoji Sentiment Ranking
  v1.0 (Kralj Novak et al., 2015 — see `priv/emoji_sentiment/`)
  covering ~750 emoji with per-emoji negative/neutral/positive
  proportions and an aggregate score in `[-1.0, 1.0]`.

  """

  # A curated lookup of common emoji -> CLDR-style short names (no colons).
  # Source: hand-picked from CLDR annotations for the most-used emoji.
  @short_names %{
    "😀" => "grinning_face",
    "😃" => "grinning_face_with_big_eyes",
    "😄" => "grinning_face_with_smiling_eyes",
    "😁" => "beaming_face_with_smiling_eyes",
    "😆" => "grinning_squinting_face",
    "😅" => "grinning_face_with_sweat",
    "🤣" => "rolling_on_the_floor_laughing",
    "😂" => "face_with_tears_of_joy",
    "🙂" => "slightly_smiling_face",
    "🙃" => "upside_down_face",
    "😉" => "winking_face",
    "😊" => "smiling_face_with_smiling_eyes",
    "😇" => "smiling_face_with_halo",
    "🥰" => "smiling_face_with_hearts",
    "😍" => "smiling_face_with_heart_eyes",
    "🤩" => "star_struck",
    "😘" => "face_blowing_a_kiss",
    "😗" => "kissing_face",
    "😚" => "kissing_face_with_closed_eyes",
    "😙" => "kissing_face_with_smiling_eyes",
    "😋" => "face_savoring_food",
    "😛" => "face_with_tongue",
    "😜" => "winking_face_with_tongue",
    "🤪" => "zany_face",
    "😝" => "squinting_face_with_tongue",
    "🤑" => "money_mouth_face",
    "🤗" => "smiling_face_with_open_hands",
    "🤔" => "thinking_face",
    "🤨" => "face_with_raised_eyebrow",
    "😐" => "neutral_face",
    "😑" => "expressionless_face",
    "😶" => "face_without_mouth",
    "😏" => "smirking_face",
    "😒" => "unamused_face",
    "🙄" => "face_with_rolling_eyes",
    "😬" => "grimacing_face",
    "🤥" => "lying_face",
    "😌" => "relieved_face",
    "😔" => "pensive_face",
    "😪" => "sleepy_face",
    "😴" => "sleeping_face",
    "😷" => "face_with_medical_mask",
    "🤒" => "face_with_thermometer",
    "🤕" => "face_with_head_bandage",
    "🤢" => "nauseated_face",
    "🤮" => "face_vomiting",
    "🤧" => "sneezing_face",
    "🥵" => "hot_face",
    "🥶" => "cold_face",
    "🥴" => "woozy_face",
    "😵" => "dizzy_face",
    "🤯" => "exploding_head",
    "🥳" => "partying_face",
    "😎" => "smiling_face_with_sunglasses",
    "🤓" => "nerd_face",
    "😕" => "confused_face",
    "😟" => "worried_face",
    "🙁" => "slightly_frowning_face",
    "☹" => "frowning_face",
    "😮" => "face_with_open_mouth",
    "😯" => "hushed_face",
    "😲" => "astonished_face",
    "😳" => "flushed_face",
    "🥺" => "pleading_face",
    "😦" => "frowning_face_with_open_mouth",
    "😧" => "anguished_face",
    "😨" => "fearful_face",
    "😰" => "anxious_face_with_sweat",
    "😥" => "sad_but_relieved_face",
    "😢" => "crying_face",
    "😭" => "loudly_crying_face",
    "😱" => "face_screaming_in_fear",
    "😖" => "confounded_face",
    "😣" => "persevering_face",
    "😞" => "disappointed_face",
    "😓" => "downcast_face_with_sweat",
    "😩" => "weary_face",
    "😫" => "tired_face",
    "🥱" => "yawning_face",
    "😤" => "face_with_steam_from_nose",
    "😡" => "pouting_face",
    "😠" => "angry_face",
    "🤬" => "face_with_symbols_on_mouth",
    "😈" => "smiling_face_with_horns",
    "👿" => "angry_face_with_horns",
    "💀" => "skull",
    "💩" => "pile_of_poo",
    "🤡" => "clown_face",
    "👻" => "ghost",
    "👽" => "alien",
    "👾" => "alien_monster",
    "🤖" => "robot",

    # Hearts
    "❤" => "red_heart",
    "🧡" => "orange_heart",
    "💛" => "yellow_heart",
    "💚" => "green_heart",
    "💙" => "blue_heart",
    "💜" => "purple_heart",
    "🤎" => "brown_heart",
    "🖤" => "black_heart",
    "🤍" => "white_heart",
    "💔" => "broken_heart",

    # Hands
    "👍" => "thumbs_up",
    "👎" => "thumbs_down",
    "👌" => "ok_hand",
    "✌" => "victory_hand",
    "🤞" => "crossed_fingers",
    "🤟" => "love_you_gesture",
    "🤘" => "sign_of_the_horns",
    "🤙" => "call_me_hand",
    "👈" => "backhand_index_pointing_left",
    "👉" => "backhand_index_pointing_right",
    "👆" => "backhand_index_pointing_up",
    "👇" => "backhand_index_pointing_down",
    "☝" => "index_pointing_up",
    "✋" => "raised_hand",
    "🤚" => "raised_back_of_hand",
    "🖐" => "hand_with_fingers_splayed",
    "🖖" => "vulcan_salute",
    "👋" => "waving_hand",
    "🤝" => "handshake",
    "🙏" => "folded_hands",
    "👏" => "clapping_hands",
    "🙌" => "raising_hands",

    # Common objects / symbols
    "🔥" => "fire",
    "⭐" => "star",
    "✨" => "sparkles",
    "🎉" => "party_popper",
    "🎊" => "confetti_ball",
    "🎈" => "balloon",
    "🎁" => "wrapped_gift",
    "🏆" => "trophy",
    "🥇" => "first_place_medal",
    "🥈" => "second_place_medal",
    "🥉" => "third_place_medal",
    "💯" => "hundred_points",
    "✅" => "check_mark_button",
    "❌" => "cross_mark",
    "⚠" => "warning",
    "🚨" => "police_car_light",
    "💡" => "light_bulb",
    "📌" => "pushpin",
    "🔗" => "link",
    "📎" => "paperclip",
    "📝" => "memo",
    "📚" => "books",
    "💻" => "laptop",
    "📱" => "mobile_phone",
    "⌚" => "watch",
    "🎵" => "musical_note",
    "🎶" => "musical_notes",
    "☕" => "hot_beverage",
    "🍺" => "beer_mug",
    "🍕" => "pizza",
    "🍔" => "hamburger",
    "🌍" => "globe_showing_europe_africa",
    "🌎" => "globe_showing_americas",
    "🌏" => "globe_showing_asia_australia",
    "☀" => "sun",
    "🌙" => "crescent_moon",
    "⛅" => "sun_behind_cloud",
    "☁" => "cloud",
    "❄" => "snowflake",
    "⚡" => "high_voltage",
    "💧" => "droplet",
    "🌈" => "rainbow"
  }

  @reverse Enum.into(@short_names, %{}, fn {emoji, name} -> {name, emoji} end)

  @emoji_sentiment_path "priv/emoji_sentiment/emoji_sentiment_v1.csv"
  @external_resource @emoji_sentiment_path

  # Parse the Emoji Sentiment Ranking v1.0 CSV at compile time.
  # Header: Emoji,Unicode codepoint,Occurrences,Position,Negative,Neutral,Positive,Unicode name,Unicode block
  @emoji_sentiments @emoji_sentiment_path
                    |> File.read!()
                    |> String.split(~r/\r?\n/, trim: true)
                    |> Enum.drop(1)
                    |> Enum.flat_map(fn line ->
                      case String.split(line, ",", parts: 9) do
                        [emoji, _cp, occ, _pos, neg, neu, pos, name, _block] ->
                          occurrences = String.to_integer(occ)
                          negative = String.to_integer(neg)
                          neutral = String.to_integer(neu)
                          positive = String.to_integer(pos)

                          score =
                            if occurrences > 0,
                              do: (positive - negative) / occurrences,
                              else: 0.0

                          [
                            {emoji,
                             %{
                               emoji: emoji,
                               occurrences: occurrences,
                               negative: negative,
                               neutral: neutral,
                               positive: positive,
                               score: score,
                               name: name
                             }}
                          ]

                        _ ->
                          []
                      end
                    end)
                    |> Map.new()

  @doc """
  Returns a list of every emoji found in the text, in order of
  appearance.

  ### Arguments

  * `text` is the input string.

  ### Returns

  * A list of single-emoji strings. Emoji ZWJ sequences (e.g.
    family emoji) currently appear as their constituent pictographs
    rather than as a single grouped sequence.

  ### Examples

      iex> Text.Emoji.extract("Hello 😀 world 🎉")
      ["😀", "🎉"]

      iex> Text.Emoji.extract("no emoji here")
      []

  """
  # Build the Extended_Pictographic character class at compile time
  # from `Unicode.Emoji.emoji(:extended_pictographic)` ranges. This
  # avoids depending on PCRE2's `\p{Extended_Pictographic}` property
  # name, which varies in support across OTP-bundled PCRE2 versions
  # (notably failing on some OTP 26/27 builds).
  @extended_pictographic_class Unicode.Emoji.emoji()
                               |> Map.get(:extended_pictographic, [])
                               |> Enum.map_join(fn
                                 {a, a} ->
                                   "\\x{#{Integer.to_string(a, 16)}}"

                                 {a, b} ->
                                   "\\x{#{Integer.to_string(a, 16)}}-\\x{#{Integer.to_string(b, 16)}}"
                               end)
                               |> then(&("[" <> &1 <> "]"))

  @extended_pictographic_regex Regex.compile!(@extended_pictographic_class, "u")

  @spec extract(String.t()) :: [String.t()]
  def extract(text) when is_binary(text) do
    Regex.scan(@extended_pictographic_regex, text)
    |> Enum.map(&hd/1)
  end

  @doc """
  Returns the number of emoji in the text.

  ### Examples

      iex> Text.Emoji.count("Hello 😀 world 🎉")
      2

  """
  @spec count(String.t()) :: non_neg_integer()
  def count(text) when is_binary(text), do: length(extract(text))

  @doc """
  Returns true when the text contains at least one emoji.

  ### Examples

      iex> Text.Emoji.contains?("hello 😀")
      true

      iex> Text.Emoji.contains?("hello")
      false

  """
  @spec contains?(String.t()) :: boolean()
  def contains?(text) when is_binary(text) do
    Regex.match?(@extended_pictographic_regex, text)
  end

  @doc """
  Removes every emoji from the text.

  ### Examples

      iex> Text.Emoji.strip("Hello 😀 world 🎉!")
      "Hello  world !"

  """
  @spec strip(String.t()) :: String.t()
  def strip(text) when is_binary(text) do
    Regex.replace(@extended_pictographic_regex, text, "")
  end

  @doc """
  Replaces emoji in the text with `:short_name:` placeholders.

  Emoji not in the bundled lookup are left as-is.

  ### Arguments

  * `text` is the input string.

  ### Options

  * `:delimiter` is the delimiter character used around the short
    name. Default `":"` produces `:smile:`.

  ### Returns

  * The text with known emoji replaced by their short names.

  ### Examples

      iex> Text.Emoji.demojize("Hello 😀 world")
      "Hello :grinning_face: world"

      iex> Text.Emoji.demojize("rare emoji 🪿")
      "rare emoji 🪿"

  """
  @spec demojize(String.t(), keyword()) :: String.t()
  def demojize(text, options \\ []) when is_binary(text) do
    delimiter = Keyword.get(options, :delimiter, ":")
    lookup = short_names()

    Regex.replace(@extended_pictographic_regex, text, fn match ->
      case Map.get(lookup, match) do
        nil -> match
        name -> delimiter <> name <> delimiter
      end
    end)
  end

  @doc """
  Replaces `:short_name:` placeholders with their emoji.

  Unknown short names are left as-is.

  ### Arguments

  * `text` is the input string.

  ### Options

  * `:delimiter` is the delimiter character around the short name.
    Default `":"`.

  ### Returns

  * The text with short names replaced by emoji.

  ### Examples

      iex> Text.Emoji.emojize("Hello :grinning_face: world")
      "Hello 😀 world"

  """
  @spec emojize(String.t(), keyword()) :: String.t()
  def emojize(text, options \\ []) when is_binary(text) do
    delimiter = Keyword.get(options, :delimiter, ":")
    delim_pattern = Regex.escape(delimiter)
    pattern = Regex.compile!(delim_pattern <> "([a-z0-9_]+)" <> delim_pattern)
    reverse = reverse_lookup()

    Regex.replace(pattern, text, fn full, name ->
      case Map.get(reverse, name) do
        nil -> full
        emoji -> emoji
      end
    end)
  end

  @doc """
  Returns the bundled sentiment record for a single emoji.

  The data is the Emoji Sentiment Ranking v1.0 (Kralj Novak et al.,
  2015), licensed CC-BY-SA 3.0. Coverage is ~750 of the most-used
  emoji in tweets at the time of the study; rare emoji return `nil`.

  ### Arguments

  * `emoji` is a single-emoji string. Surface form must match the
    upstream entry exactly (no skin-tone or ZWJ-sequence variants).

  ### Returns

  * A map with keys `:emoji`, `:occurrences`, `:negative`,
    `:neutral`, `:positive`, `:score` (range `[-1.0, 1.0]`), and
    `:name` (Unicode name). Returns `nil` if the emoji is not in
    the ranking.

  ### Examples

      iex> %{score: score} = Text.Emoji.sentiment("😂")
      iex> score > 0.0
      true

      iex> Text.Emoji.sentiment("not_an_emoji")
      nil

  """
  @spec sentiment(String.t()) ::
          %{
            emoji: String.t(),
            occurrences: non_neg_integer(),
            negative: non_neg_integer(),
            neutral: non_neg_integer(),
            positive: non_neg_integer(),
            score: float(),
            name: String.t()
          }
          | nil
  def sentiment(emoji) when is_binary(emoji) do
    Map.get(@emoji_sentiments, emoji)
  end

  @doc """
  Returns the aggregate sentiment of every known emoji in a text.

  Each emoji's score is weighted by its corpus `:occurrences` so
  that high-confidence emoji dominate noisy ones — matching the
  weighted-average approach used by the original paper. Emoji not
  in the ranking are skipped.

  ### Arguments

  * `text` is the input string.

  ### Returns

  * `{score, count}` where `score` is a float in `[-1.0, 1.0]` and
    `count` is the number of emoji that contributed. Returns `nil`
    when the text contains no scoreable emoji.

  ### Examples

      iex> {score, 2} = Text.Emoji.text_sentiment("Great day 😂❤")
      iex> score > 0.0
      true

      iex> Text.Emoji.text_sentiment("no emoji here")
      nil

  """
  @spec text_sentiment(String.t()) :: {float(), pos_integer()} | nil
  def text_sentiment(text) when is_binary(text) do
    {weighted, weight, count} =
      text
      |> extract()
      |> Enum.reduce({0.0, 0, 0}, fn emoji, {w_acc, occ_acc, n} ->
        case Map.get(@emoji_sentiments, emoji) do
          nil -> {w_acc, occ_acc, n}
          %{score: s, occurrences: o} -> {w_acc + s * o, occ_acc + o, n + 1}
        end
      end)

    cond do
      count == 0 -> nil
      weight == 0 -> {0.0, count}
      true -> {weighted / weight, count}
    end
  end

  @doc """
  Adds project-specific emoji to the runtime short-name lookup.

  Useful for custom platform emoji or for filling in gaps in the
  bundled set.

  ### Arguments

  * `entries` is a map or keyword list of `emoji => short_name`
    pairs (where `short_name` is the bare name without colons).

  ### Returns

  * `:ok` on success.

  """
  @spec add_emoji(map() | keyword()) :: :ok
  def add_emoji(entries) do
    new_forward =
      entries
      |> Enum.into(%{})
      |> Map.new(fn {k, v} -> {to_string(k), to_string(v)} end)

    new_reverse =
      Enum.into(new_forward, %{}, fn {emoji, name} -> {name, emoji} end)

    forward = :persistent_term.get({__MODULE__, :forward}, %{})
    reverse = :persistent_term.get({__MODULE__, :reverse}, %{})

    :persistent_term.put({__MODULE__, :forward}, Map.merge(forward, new_forward))
    :persistent_term.put({__MODULE__, :reverse}, Map.merge(reverse, new_reverse))
    :ok
  end

  defp short_names do
    Map.merge(@short_names, :persistent_term.get({__MODULE__, :forward}, %{}))
  end

  defp reverse_lookup do
    Map.merge(@reverse, :persistent_term.get({__MODULE__, :reverse}, %{}))
  end
end
