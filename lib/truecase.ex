defmodule Text.Truecase do
  @moduledoc """
  Restore case to text that has been lowercased.

  Useful as a preprocessing step when downstream tooling — POS
  tagging, NER, sentiment classifiers — was trained on properly
  cased text but the input has been lowercased earlier in the
  pipeline (a common artefact of search and chat systems).

  The module uses a small curated lexicon of words with non-default
  casing (proper nouns, brand names, common acronyms) plus a
  sentence-boundary-aware capitalization pass on the first word of
  each sentence. The lexicon can be extended at runtime via
  `add_terms/1` for project-specific vocabulary.

  This is intentionally minimal: a frequency-based truecaser trained
  on a cased corpus would be more accurate, but harder to bundle
  and unnecessary for the common cleanup case. The exception list
  below covers the words that show up most often in mixed-domain
  text.

  """

  # A curated list of words that typically appear with non-default casing.
  # Format: lowercase form -> canonical form. Default is lowercase, so
  # entries whose canonical form is just `Capitalized` are listed.
  @lexicon %{
    # Days, months
    "monday" => "Monday",
    "tuesday" => "Tuesday",
    "wednesday" => "Wednesday",
    "thursday" => "Thursday",
    "friday" => "Friday",
    "saturday" => "Saturday",
    "sunday" => "Sunday",
    "january" => "January",
    "february" => "February",
    "march" => "March",
    "april" => "April",
    "may" => "May",
    "june" => "June",
    "july" => "July",
    "august" => "August",
    "september" => "September",
    "october" => "October",
    "november" => "November",
    "december" => "December",

    # Common languages / nationalities (subset)
    "english" => "English",
    "french" => "French",
    "german" => "German",
    "spanish" => "Spanish",
    "italian" => "Italian",
    "japanese" => "Japanese",
    "chinese" => "Chinese",
    "russian" => "Russian",
    "portuguese" => "Portuguese",
    "korean" => "Korean",
    "arabic" => "Arabic",
    "american" => "American",
    "british" => "British",
    "european" => "European",
    "asian" => "Asian",
    "african" => "African",

    # Common countries (subset)
    "australia" => "Australia",
    "austria" => "Austria",
    "belgium" => "Belgium",
    "brazil" => "Brazil",
    "canada" => "Canada",
    "china" => "China",
    "denmark" => "Denmark",
    "egypt" => "Egypt",
    "england" => "England",
    "finland" => "Finland",
    "france" => "France",
    "germany" => "Germany",
    "greece" => "Greece",
    "india" => "India",
    "indonesia" => "Indonesia",
    "ireland" => "Ireland",
    "israel" => "Israel",
    "italy" => "Italy",
    "japan" => "Japan",
    "mexico" => "Mexico",
    "netherlands" => "Netherlands",
    "norway" => "Norway",
    "pakistan" => "Pakistan",
    "poland" => "Poland",
    "portugal" => "Portugal",
    "russia" => "Russia",
    "scotland" => "Scotland",
    "spain" => "Spain",
    "sweden" => "Sweden",
    "switzerland" => "Switzerland",
    "turkey" => "Turkey",
    "ukraine" => "Ukraine",
    "vietnam" => "Vietnam",
    "wales" => "Wales",

    # Common cities (subset)
    "amsterdam" => "Amsterdam",
    "athens" => "Athens",
    "bangkok" => "Bangkok",
    "beijing" => "Beijing",
    "berlin" => "Berlin",
    "boston" => "Boston",
    "brussels" => "Brussels",
    "cairo" => "Cairo",
    "chicago" => "Chicago",
    "delhi" => "Delhi",
    "dubai" => "Dubai",
    "dublin" => "Dublin",
    "geneva" => "Geneva",
    "hamburg" => "Hamburg",
    "helsinki" => "Helsinki",
    "hong" => "Hong",
    "istanbul" => "Istanbul",
    "jakarta" => "Jakarta",
    "jerusalem" => "Jerusalem",
    "lagos" => "Lagos",
    "lima" => "Lima",
    "lisbon" => "Lisbon",
    "london" => "London",
    "madrid" => "Madrid",
    "manila" => "Manila",
    "melbourne" => "Melbourne",
    "milan" => "Milan",
    "moscow" => "Moscow",
    "mumbai" => "Mumbai",
    "munich" => "Munich",
    "nairobi" => "Nairobi",
    "paris" => "Paris",
    "prague" => "Prague",
    "rome" => "Rome",
    "seoul" => "Seoul",
    "shanghai" => "Shanghai",
    "singapore" => "Singapore",
    "stockholm" => "Stockholm",
    "sydney" => "Sydney",
    "taipei" => "Taipei",
    "tokyo" => "Tokyo",
    "toronto" => "Toronto",
    "vienna" => "Vienna",
    "warsaw" => "Warsaw",
    "york" => "York",
    "zurich" => "Zurich",

    # Common organizations / acronyms
    "nasa" => "NASA",
    "fbi" => "FBI",
    "cia" => "CIA",
    "ibm" => "IBM",
    "ieee" => "IEEE",
    "nato" => "NATO",
    "un" => "UN",
    "uk" => "UK",
    "usa" => "USA",
    "us" => "US",
    "eu" => "EU",
    "uefa" => "UEFA",
    "fifa" => "FIFA",
    "wto" => "WTO",
    "imf" => "IMF",
    "oecd" => "OECD",
    "who" => "WHO",
    "unesco" => "UNESCO",
    "unicef" => "UNICEF",
    "nyse" => "NYSE",
    "nasdaq" => "NASDAQ",
    "html" => "HTML",
    "css" => "CSS",
    "json" => "JSON",
    "xml" => "XML",
    "api" => "API",
    "url" => "URL",
    "uri" => "URI",
    "http" => "HTTP",
    "https" => "HTTPS",
    "ssl" => "SSL",
    "tls" => "TLS",
    "tcp" => "TCP",
    "udp" => "UDP",
    "dns" => "DNS",
    "sql" => "SQL",
    "ai" => "AI",
    "ml" => "ML",
    "gpu" => "GPU",
    "cpu" => "CPU",
    "ram" => "RAM",
    "ssd" => "SSD",
    "usb" => "USB",
    "pdf" => "PDF",

    # Brand / company names with non-default casing
    "iphone" => "iPhone",
    "ipad" => "iPad",
    "ipod" => "iPod",
    "imac" => "iMac",
    "macos" => "macOS",
    "ios" => "iOS",
    "ebay" => "eBay",
    "youtube" => "YouTube",
    "javascript" => "JavaScript",
    "typescript" => "TypeScript",
    "github" => "GitHub",
    "gitlab" => "GitLab",
    "linkedin" => "LinkedIn",
    "paypal" => "PayPal",
    "wifi" => "WiFi",
    "bluetooth" => "Bluetooth",
    "android" => "Android",
    "linux" => "Linux",
    "windows" => "Windows",
    "macbook" => "MacBook",
    "openai" => "OpenAI",
    "deepmind" => "DeepMind",
    "anthropic" => "Anthropic",
    "google" => "Google",
    "microsoft" => "Microsoft",
    "apple" => "Apple",
    "amazon" => "Amazon",
    "facebook" => "Facebook",
    "twitter" => "Twitter",
    "netflix" => "Netflix",
    "tesla" => "Tesla",
    "nvidia" => "Nvidia"
  }

  @doc """
  Restores casing in lowercased text.

  ### Arguments

  * `text` is the (possibly lowercased) input string.

  ### Options

  * `:capitalize_sentences` — if `true` (the default), capitalizes
    the first letter of each sentence after applying the lexicon.

  ### Returns

  * The text with proper nouns, acronyms, and brand names
    re-capitalized, sentence starts capitalized when requested,
    and other words left as-is.

  ### Examples

      iex> Text.Truecase.truecase("i visited london in july.")
      "I visited London in July."

      iex> Text.Truecase.truecase("the api returned json.")
      "The API returned JSON."

      iex> Text.Truecase.truecase("apple released the iphone.")
      "Apple released the iPhone."

  """
  @spec truecase(String.t(), keyword()) :: String.t()
  def truecase(text, options \\ []) when is_binary(text) do
    capitalize? = Keyword.get(options, :capitalize_sentences, true)
    lexicon = lexicon()

    base =
      Regex.replace(~r/\b\p{L}[\p{L}']*\b/u, text, fn match ->
        Map.get(lexicon, String.downcase(match), match)
      end)

    if capitalize?, do: capitalize_sentences(base), else: base
  end

  @doc """
  Adds project-specific casings to the runtime lexicon.

  Useful for product names, internal acronyms, and proper nouns
  that aren't covered by the bundled list.

  ### Arguments

  * `terms` is a map or keyword list of `lowercase => Canonical`
    pairs.

  ### Returns

  * `:ok` on success.

  """
  @spec add_terms(map() | keyword()) :: :ok
  def add_terms(terms) do
    new_entries =
      terms
      |> Enum.into(%{})
      |> Map.new(fn {k, v} -> {String.downcase(to_string(k)), to_string(v)} end)

    current = :persistent_term.get({__MODULE__, :extra}, %{})
    :persistent_term.put({__MODULE__, :extra}, Map.merge(current, new_entries))
    :ok
  end

  defp lexicon do
    Map.merge(@lexicon, :persistent_term.get({__MODULE__, :extra}, %{}))
  end

  defp capitalize_sentences(text) do
    Regex.replace(~r/(^|[.!?]\s+)(\p{Ll})/u, text, fn _, prefix, letter ->
      prefix <> String.upcase(letter)
    end)
  end
end
