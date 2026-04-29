defmodule Text.Emoji do
  @moduledoc """
  Emoji detection and short-name conversion.

  Detection uses the Unicode `Extended_Pictographic` property, so it
  picks up the full emoji repertoire including newer additions
  without needing a per-release data update.

  Short-name conversion (`demojize/2`, `emojize/2`) uses a small
  bundled lookup of the most common emoji. It is not a complete
  CLDR annotation set; rare emoji round-trip as themselves. Users
  can extend the lookup at runtime via `add_emoji/1`.

  Sentiment scoring of emoji is a planned follow-up — the bundled
  AFINN lexicon already covers emoticons (`:-)`, `:(`), and the
  Bumblebee-backed sentiment model handles emoji directly.

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
  @spec extract(String.t()) :: [String.t()]
  def extract(text) when is_binary(text) do
    Regex.scan(~r/\p{Extended_Pictographic}/u, text)
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
    Regex.match?(~r/\p{Extended_Pictographic}/u, text)
  end

  @doc """
  Removes every emoji from the text.

  ### Examples

      iex> Text.Emoji.strip("Hello 😀 world 🎉!")
      "Hello  world !"

  """
  @spec strip(String.t()) :: String.t()
  def strip(text) when is_binary(text) do
    Regex.replace(~r/\p{Extended_Pictographic}/u, text, "")
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

    Regex.replace(~r/\p{Extended_Pictographic}/u, text, fn match ->
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
