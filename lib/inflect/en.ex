defmodule Text.Inflect.En do
  @moduledoc """
  Pluralisation for the English language based on the paper
  [An Algorithmic Approach to English Pluralization](http://users.monash.edu/~damian/papers/HTML/Plurals.html).

  """
  @saved_data_path "priv/inflection/en/en.etf"
  @external_resource @saved_data_path

  @inflections File.read!(@saved_data_path)
               |> :erlang.binary_to_term()

  @doc false
  def inflections do
    @inflections
  end

  @doc """
  Pluralize an english noun, pronoun,
  verb or adjective.

  ### Arguments

  * `word` is any English word.

  * `mode` is `:modern` or `:classical`. The
    default is `:modern`. This applies to
    nouns only.

  ### Returns

  * a `String` representing the pluralized word.

  ### Notes

  `mode` when `:classical` applies pluralization
  on latin nouns in english but with latin
  suffixes.

  ### Examples

      iex> Text.Inflect.En.pluralize "fish"
      "fish"

      iex> Text.Inflect.En.pluralize "soliloquy"
      "soliloquies"

      iex> Text.Inflect.En.pluralize "genius", :classical
      "genii"

      iex> Text.Inflect.En.pluralize "has"
      "have"

      iex> Text.Inflect.En.pluralize "catches"
      "catch"

      iex> Text.Inflect.En.pluralize "child's"
      "children's"

      iex> Text.Inflect.En.pluralize "Mary's"
      "Marys'"

  """

  def pluralize(word, mode \\ :modern) do
    # Handle known adjectives...
    #         try steps 2 through 4 of Algorithm 3
    # Handle known verbs...
    #         try steps 2 through 5 of Algorithm 2
    # third_person_singular_s?(word) ||
    # Handle singular nouns ending in -s (ethos, axis, etc. - see Tables A.2, A.3, A.16, A.22, and A.23)...
    #         if word is a noun ending in -s,
    #                 try steps 2 through 13 of Algorithm 1
    pluralize_adjective_or_verb(word) || pluralize_noun_or_verb(word, mode)
  end

  # First pass: adjectives (articles, possessives, genitives) and the
  # simple irregular / third-person verb forms.
  defp pluralize_adjective_or_verb(word) do
    indefinite_article?(word) ||
      possessive_pronoun?(word) ||
      genetive?(word) ||
      non_inflecting_verb?(word) ||
      irregular_verb?(word) ||
      third_person_singular?(word)
  end

  # Second pass: words ending in -s go straight to noun pluralization;
  # everything else tries the remaining verb rules first.
  defp pluralize_noun_or_verb(word, mode) do
    if suffix?(word, "s") do
      pluralize_noun(word, mode)
    else
      # Handle 3rd person singular verbs (that is, any other words ending in -s)...
      #         try steps 4 and 5 of Algorithm 2
      # Treat the word as a noun...
      #         try steps 2 through 13 of Algorithm 1
      third_person_singular?(word) ||
        third_person_singular_s?(word) ||
        pluralize_noun(word, mode)
    end
  end

  @doc """
  Singularize an English word.

  Inverts `pluralize/2`: given a plural noun (or pronoun), returns its
  singular form. Inputs that are already singular, or that aren't
  recognised as a plural, are returned unchanged.

  ### Arguments

  * `word` is the word to singularize.

  * `mode` is one of `:modern` (default) or `:classical`. The
    classical mode uses Latin/Greek classical singulars where
    applicable (e.g. `octopodes → octopus` in classical, vs.
    `octopuses → octopus` in modern).

  ### Returns

  * The singular form as a string. Words that don't appear plural
    (or that have no known singular) are returned unchanged.

  ### Examples

      iex> Text.Inflect.En.singularize "mice"
      "mouse"

      iex> Text.Inflect.En.singularize "children"
      "child"

      iex> Text.Inflect.En.singularize "octopuses"
      "octopus"

      iex> Text.Inflect.En.singularize "octopodes", :classical
      "octopus"

      iex> Text.Inflect.En.singularize "cities"
      "city"

      iex> Text.Inflect.En.singularize "knives"
      "knife"

  """
  def singularize(word, mode \\ :modern) do
    Text.Inflect.En.Singularize.pronoun?(word, mode) ||
      Text.Inflect.En.Singularize.non_inflecting?(word, mode) ||
      Text.Inflect.En.Singularize.irregular_noun?(word, mode) ||
      explicit_singular(word) ||
      round_trip_candidate(word, mode) ||
      singularize_noun(word, mode)
  end

  # Unambiguous English plural-suffix rewrites. These take priority
  # over the round-trip search because the original `pluralize_noun/2`
  # has known gaps for some sibilant-ending bases (`box`, `kiss`).
  # Common Greek-derived singulars whose plurals are formed by
  # `-is` → `-es` (analyses → analysis, crises → crisis). Without
  # this whitelist the round-trip would prefer the shorter
  # `analyse`/`crise` form because the original `pluralize_noun/2`
  # accepts both as valid singulars.
  @greek_is_es_singulars MapSet.new(~w(
                             analysis axis basis crisis diagnosis ellipsis
                             emphasis genesis hypothesis nemesis oasis
                             paralysis prognosis psychosis synopsis thesis
                           ))

  # Common English `-us` nouns whose plurals are formed by `-uses`.
  # Used in `explicit_singular/1` because the original Conway-style
  # `pluralize_noun/2` doesn't reliably round-trip these (it returns
  # e.g. `statuss` for `status`).
  @us_base_singulars MapSet.new(~w(
                         abacus apparatus apropos asparagus bonus bus cactus
                         calculus campus census circus citrus consensus
                         corpus cosmos crocus crocus discus eros
                         exodus focus fungus genius genus hippopotamus
                         impetus iris isthmus locus lotus nautilus
                         nimbus nucleus omnibus opus prospectus radius
                         status stimulus stylus surplus syllabus terminus
                         thesaurus typhus uterus virus walrus
                       ))

  # Common English words ending in `-oe` whose plurals are formed by a
  # plain `-s` (`shoe`/`shoes`, `toe`/`toes`). Used to disambiguate
  # `-oes` inputs: when the trim-`-s` candidate is in this list, prefer
  # it over the trim-`-es` form. Without this list `shoes` would
  # wrongly land at `sho` because `sho + es = shoes` is a valid
  # round-trip.
  @oe_base_singulars MapSet.new(~w(
                         shoe toe canoe foe doe hoe woe oboe horseshoe
                         tiptoe overshoe snowshoe
                       ))

  defp explicit_singular(word) do
    if String.length(word) <= 3 do
      nil
    else
      explicit_singular_by_suffix(word) ||
        explicit_singular_by_whitelist(word) ||
        explicit_singular_by_o(word)
    end
  end

  # Simple suffix-driven singularization for -ies, -sses, -shes, -ches,
  # -xes, and -zes plurals.
  defp explicit_singular_by_suffix(word) do
    cond do
      String.ends_with?(word, "ies") ->
        String.replace_suffix(word, "ies", "y")

      String.ends_with?(word, "sses") ->
        String.replace_suffix(word, "sses", "ss")

      String.ends_with?(word, "shes") or String.ends_with?(word, "ches") ->
        String.replace_suffix(word, "es", "")

      String.ends_with?(word, "xes") or String.ends_with?(word, "zes") ->
        String.replace_suffix(word, "es", "")

      true ->
        nil
    end
  end

  # Whitelist-driven singularization: -uses from -us bases (genius,
  # status, virus) and Greek -es plurals (analyses → analysis).
  defp explicit_singular_by_whitelist(word) do
    cond do
      String.ends_with?(word, "uses") and
          MapSet.member?(@us_base_singulars, String.replace_suffix(word, "es", "")) ->
        String.replace_suffix(word, "es", "")

      candidate = greek_is_singular(word) ->
        candidate

      true ->
        nil
    end
  end

  # -oes handling: whitelisted -oe bases (shoes → shoe) and default
  # consonant-final -o bases (potatoes → potato).
  defp explicit_singular_by_o(word) do
    cond do
      not String.ends_with?(word, "oes") ->
        nil

      MapSet.member?(@oe_base_singulars, String.replace_suffix(word, "s", "")) ->
        String.replace_suffix(word, "s", "")

      consonant_before_oes?(word) ->
        String.replace_suffix(word, "es", "")

      true ->
        nil
    end
  end

  defp greek_is_singular(word) do
    if String.ends_with?(word, "es") do
      candidate = String.replace_suffix(word, "es", "is")
      if MapSet.member?(@greek_is_es_singulars, candidate), do: candidate
    end
  end

  # `true` if the character immediately before the trailing `oes` is a
  # consonant — distinguishing `potato-es`, `hero-es` (consonant + o
  # base) from `aloes` (a-l-o-es, vowel before).
  defp consonant_before_oes?(word) do
    n = String.length(word)

    if n >= 4 do
      char = String.at(word, n - 4)
      char != nil and char not in ["a", "e", "i", "o", "u"]
    else
      false
    end
  end

  # Generate plausible singular candidates from `word` and return the
  # first whose `pluralize_noun/2` round-trips back to `word`. This
  # leverages the existing pluralization data tables to validate
  # candidates rather than trying to enumerate every English plural
  # ending.
  defp round_trip_candidate(word, mode) do
    word
    |> singular_candidates()
    |> Enum.find(fn candidate ->
      candidate != word and pluralize_noun(candidate, mode) == word
    end)
  end

  # The candidate suffix transformations, in roughly most-to-least
  # specific order. Each candidate is one of the plausible base forms
  # for an English plural ending in `-s`.
  defp singular_candidates(word) do
    if String.length(word) <= 2 do
      [word]
    else
      [
        # `-ies` → `-y` (cities → city)
        if(String.ends_with?(word, "ies"),
          do: String.replace_suffix(word, "ies", "y")
        ),

        # `-ves` → `-fe` (knives → knife)
        if(String.ends_with?(word, "ves"),
          do: String.replace_suffix(word, "ves", "fe")
        ),

        # `-ves` → `-f`  (leaves → leaf)
        if(String.ends_with?(word, "ves"),
          do: String.replace_suffix(word, "ves", "f")
        ),

        # `-uses` → `-us` (genius → geniuses, status → statuses).
        # Tried before plain `-s` trim so that `-us` bases beat
        # `-use` bases when `pluralize_noun/2` accepts both. The
        # round-trip filters out cases where the `-us` candidate
        # doesn't pluralize back to the input (`hous` → not
        # `houses`).
        if(String.ends_with?(word, "uses"),
          do: String.replace_suffix(word, "es", "")
        ),

        # `-s` → trim (cats → cat, houses → house, shoes → shoe).
        # Tried before `-es` trim so that bases ending in `-e`
        # (`shoe`, `toe`) win over the dictionary-less alternative
        # `sho`/`to`. Cases that genuinely need `-es` trim (potato,
        # hero) are caught upstream by `explicit_singular/1`.
        if(String.ends_with?(word, "s"),
          do: String.replace_suffix(word, "s", "")
        ),

        # `-es` → trim (kisses → kiss, geniuses → genius). Last
        # resort — most -es cases are handled by explicit_singular.
        if(String.ends_with?(word, "es"),
          do: String.replace_suffix(word, "es", "")
        )
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    end
  end

  @doc """
  Singularize an English noun.

  Lower-level than `singularize/2`: skips the pronoun and
  non-inflecting checks. Useful when callers have already filtered
  the input to nouns.

  ### Arguments

  * `word` is the noun to singularize.

  * `mode` is `:modern` (default) or `:classical`.

  ### Returns

  * The singular form as a string.

  ### Examples

      iex> Text.Inflect.En.singularize_noun "octopuses"
      "octopus"

      iex> Text.Inflect.En.singularize_noun "platypodes", :classical
      "platypus"

  """
  def singularize_noun(word, mode \\ :modern) do
    singularize_by_irregular_or_classical(word, mode) ||
      singularize_by_suffix(word, mode) ||
      singularize_by_fallback(word, mode)
  end

  # Try the irregular and classical rules first — these cover the least
  # regular English/Latin plurals.
  defp singularize_by_irregular_or_classical(word, mode) do
    s = Text.Inflect.En.Singularize

    s.irregular_noun?(word, mode) ||
      s.irregular_suffix?(word, mode) ||
      s.classical_is_plural?(word, mode) ||
      s.assimilated_classical?(word, mode) ||
      s.classical?(word, mode)
  end

  # Then the suffix-driven rules (compound plurals, -ves, -y, -o).
  defp singularize_by_suffix(word, mode) do
    s = Text.Inflect.En.Singularize

    s.compound_plural?(word, mode) ||
      s.ves_plural?(word, mode) ||
      s.word_ending_in_y?(word, mode) ||
      s.o_suffix?(word, mode)
  end

  # Finally, the explicit and general fall-back rules that catch what
  # the earlier passes miss.
  defp singularize_by_fallback(word, mode) do
    s = Text.Inflect.En.Singularize

    explicit_singular(word) ||
      round_trip_candidate(word, mode) ||
      s.general?(word, mode) ||
      s.regular?(word, mode)
  end

  @doc """
  Pluralize an english noun.

  ### Arguments

  * `word` is any English noun.

  * `mode` is `:modern` or `:classical`. The
    default is `:modern`.

  ### Returns

  * a `String` representing the pluralized noun

  ### Notes

  `mode` when `:classical` applies pluralization
  on latin nouns used in english but with latin
  suffixes.

  ### Examples

      iex> Text.Inflect.En.pluralize_noun "Major general"
      "Major generals"

      iex> Text.Inflect.En.pluralize_noun "fish"
      "fish"

      iex> Text.Inflect.En.pluralize_noun "soliloquy"
      "soliloquies"

      iex> Text.Inflect.En.pluralize_noun "genius", :classical
      "genii"

      iex> Text.Inflect.En.pluralize_noun "genius"
      "geniuses"

      iex> Text.Inflect.En.pluralize_noun "platypus", :classical
      "platypodes"

      iex> Text.Inflect.En.pluralize_noun "platypus"
      "platypuses"

  """
  def pluralize_noun(word, mode \\ :modern) do
    pluralize_noun_irregular(word, mode) ||
      pluralize_noun_by_suffix(word, mode) ||
      general?(word, mode) ||
      regular?(word, mode)
  end

  # Non-inflecting, pronoun, irregular and classical rules.
  defp pluralize_noun_irregular(word, mode) do
    non_inflecting?(word, mode) ||
      pronoun?(word, mode) ||
      irregular_noun?(word, mode) ||
      irregular_suffix?(word, mode) ||
      assimilated_classical?(word, mode) ||
      classical?(word, mode)
  end

  # Compound / -ves / -y / -o suffix-driven rules.
  defp pluralize_noun_by_suffix(word, mode) do
    compound_plural?(word, mode) ||
      ves_plural?(word, mode) ||
      word_ending_in_y?(word, mode) ||
      o_suffix?(word, mode)
  end

  # Handle words that do not inflect in the plural (such as fish, travois, chassis, nationalities
  # ending in -ese etc. - see Tables A.2 and A.3)...
  #         if suffix(-fish) or suffix(-ois) or suffix(-sheep)
  #         or suffix(-deer) or suffix(-pox) or suffix(-[A-Z].*ese)
  #         or suffix(-itis) or category(-,-),
  #                 return the original noun

  defp non_inflecting?(word, mode) when is_binary(word) do
    cond do
      category?(word, "herd", mode) ->
        word

      category?(word, "nationalities", mode) ->
        word

      category?(word, "-", "-", mode) ->
        word

      true ->
        nil
    end
  end

  # Handle pronouns in the nominative, accusative, and dative (see Tables A.5), as well as
  # prepositional phrases...
  #         if the word is a pronoun,
  #                 return the specified plural of the pronoun
  #
  #         if the word is of the form: "<preposition> <pronoun>",
  #                 return "<preposition> <specified plural of pronoun>"

  defp pronoun?(word, mode) do
    if category?(word, "pronoun", mode) do
      pronoun(word, mode)
    end
  end

  # Handle standard irregular plurals (mongooses, oxen, etc. - see table A.1)...
  #         if the word has an irregular plural,
  #                 return the specified plural

  defp irregular_noun?(word, mode) do
    if category?(word, "irregular_noun", mode) do
      irregular_noun(word, mode)
    end
  end

  # Handle irregular inflections for common suffixes (synopses, mice and men, etc.)...
  #         if suffix(-man),      return inflection(-man,-men)
  #         if suffix(-[lm]ouse), return inflection(-ouse,-ice)
  #         if suffix(-tooth),    return inflection(-tooth,-teeth)
  #         if suffix(-goose),    return inflection(-goose,-geese)
  #         if suffix(-foot),     return inflection(-foot,-feet)
  #         if suffix(-zoon),     return inflection(-zoon,-zoa)
  #         if suffix(-[csx]is),  return inflection(-is,-es)

  @irregular_suffix_rules [
    {"man", "men"},
    {"louse", "lice"},
    {"mouse", "mice"},
    {"tooth", "teeth"},
    {"goose", "geese"},
    {"foot", "feet"},
    {"zoon", "zoa"},
    {"cis", "ces"},
    {"sis", "ses"},
    {"xis", "xes"}
  ]

  defp irregular_suffix?(word, _mode) do
    Enum.find_value(@irregular_suffix_rules, fn {from, to} ->
      if suffix?(word, from), do: replace_suffix(word, from, to)
    end)
  end

  # Handle fully assimilated classical inflections (vertebrae, codices, etc. - see tables A.10,
  # A.14, A.19 and A.20, and tables A.11, A.15 and A.21 if in "classical mode)...
  #         if category(-ex,-ices), return inflection(-ex,-ices)
  #         if category(-um,-a),    return inflection(-um,-a)
  #         if category(-on,-a),    return inflection(-on,-a)
  #         if category(-a,-ae),    return inflection(-a,-ae)

  defp assimilated_classical?(word, mode) do
    cond do
      category?(word, "-ex", "-ices", mode) ->
        replace_suffix(word, "ex", "ices")

      category?(word, "-um", "-a", mode) ->
        replace_suffix(word, "um", "a")

      category?(word, "-on", "-a", mode) ->
        replace_suffix(word, "on", "a")

      category?(word, "-a", "-ae", mode) ->
        replace_suffix(word, "a", "ae")

      true ->
        nil
    end
  end

  # Handle classical variants of modern inflections (stigmata, soprani, etc. - see tables A.11 to
  # A.13, A.15, A.16, A.18, A.21 to A.25)...
  #         if in classical mode,
  #                 if suffix(-trix),       return inflection(-trix,-trices)
  #                 if suffix(-eau),        return inflection(-eau,-eaux)
  #                 if suffix(-ieu),        return inflection(-ieu,-ieux)
  #                 if suffix(-..[iay]nx),  return inflection(-nx,-nges)
  #                 if category(-en,-ina),  return inflection(-en,-ina)
  #                 if category(-a,-ata),   return inflection(-a,-ata)
  #                 if category(-is,-ides), return inflection(-is,-ides)
  #                 if category(-us,-i),    return inflection(-us,-i)
  #                 if category(-us,-us),   return the original noun
  #                 if category(-o,-i),     return inflection(-o,-i)
  #                 if category(-,-i),      return inflection(-,-i)
  #                 if category(-,-im),     return inflection(-,-im)

  defp classical?(word, :classical = mode) do
    classical_by_suffix(word) || classical_by_category(word, mode)
  end

  defp classical?(word, :modern = mode) do
    if category?(word, "-us", "-i", mode) do
      replace_suffix(word, "us", "uses")
    end
  end

  # Classical rules driven by the raw word suffix (trix, eau, ieu, -nx).
  defp classical_by_suffix(word) do
    cond do
      suffix?(word, "trix") ->
        replace_suffix(word, "trix", "trices")

      suffix?(word, "eau") ->
        word <> "x"

      suffix?(word, "ieu") ->
        word <> "x"

      suffix?(word, "inx") or suffix?(word, "anx") or suffix?(word, "ynx") ->
        replace_suffix(word, "nx", "nges")

      true ->
        nil
    end
  end

  # Category-driven classical plurals: each rule is `{from, to,
  # transform}`. Categories with matching singular/plural endings use
  # `:keep` (the word is returned unchanged); the rest use either
  # `{:replace, from, to}` or `{:append, chars}`.
  @classical_category_rules [
    {"-en", "-ina", {:replace, "en", "ina"}},
    {"-a", "-ata", {:append, "ta"}},
    {"-is", "-ides", {:replace, "is", "ides"}},
    {"-us", "-i", {:replace, "us", "i"}},
    {"-us", "-us", :keep},
    {"-o", "-i", {:replace, "o", "i"}},
    {"-", "-i", {:append, "i"}},
    {"-", "-im", {:append, "im"}}
  ]

  defp classical_by_category(word, mode) do
    Enum.find_value(@classical_category_rules, fn {from, to, action} ->
      if category?(word, from, to, mode), do: apply_classical_action(word, action)
    end)
  end

  defp apply_classical_action(word, :keep), do: word
  defp apply_classical_action(word, {:replace, from, to}), do: replace_suffix(word, from, to)
  defp apply_classical_action(word, {:append, chars}), do: word <> chars

  # The suffixes -ch, -sh, and -ss all take -es in the plural (churches, classes, etc)...
  #         if suffix(-[cs]h), return inflection(-h,-hes)
  #         if suffix(-ss),    return inflection(-ss,-sses)

  defp compound_plural?(word, _mode) do
    cond do
      suffix?(word, "ch") ->
        replace_suffix(word, "h", "hes")

      suffix?(word, "sh") ->
        replace_suffix(word, "h", "hes")

      suffix?(word, "ss") ->
        replace_suffix(word, "h", "sses")

      true ->
        nil
    end
  end

  # Certain words ending in -f or -fe take -ves in the plural (lives, wolves, etc)...
  #         if suffix(-[aeo]lf) or suffix(-[^d]eaf) or suffix(-arf),
  #                 return inflection(-f,-ves)
  #
  #         if suffix(-[nlw]ife),
  #                 return inflection(-fe,-ves)

  @ves_f_suffixes ~w(alf elf olf arf)
  @ves_fe_suffixes ~w(nife life wife)

  defp ves_plural?(word, _mode) do
    cond do
      Enum.any?(@ves_f_suffixes, &suffix?(word, &1)) ->
        replace_suffix(word, "f", "ves")

      Enum.any?(@ves_fe_suffixes, &suffix?(word, &1)) ->
        replace_suffix(word, "fe", "ves")

      suffix?(word, "eaf") ->
        if String.at(word, -4) == "d", do: nil, else: replace_suffix(word, "f", "ves")

      true ->
        nil
    end
  end

  # Words ending in -y take -ys if preceded by a vowel (storeys, stays, etc.) or when a proper noun
  # (Marys, Tonys, etc.), but -ies if preceded by a consonant (stories, skies, etc.)...
  #         if suffix(-[aeiou]y), return inflection(-y,-ys)
  #         if suffix(-[A-Z].*y), return inflection(-y,-ys)
  #         if suffix(-y),        return inflection(-y,-ies)

  defp word_ending_in_y?(word, _mode) do
    cond do
      suffix?(word, "y") && vowel?(word, -2) ->
        word <> "s"

      suffix?(word, "y") && starts_with_upper?(word) ->
        word <> "s"

      suffix?(word, "y") ->
        replace_suffix(word, "y", "ies")

      true ->
        nil
    end
  end

  # Some words ending in -o take -os (lassos, solos, etc. - see tables A.17 and A.18); the rest
  # take -oes (potatoes, dominoes, etc.) However, words in which the -o is preceded by a vowel
  # always take -os (folios, bamboos)...
  #         if category(-o,-os) or suffix(-[aeiou]o),
  #                 return inflection(-o,-os)
  #
  #         if suffix(-o), return inflection(-o,-oes)

  defp o_suffix?(word, :modern = mode) do
    cond do
      category?(word, "-o", "-os", mode) ->
        word <> "s"

      suffix?(word, "o") && vowel?(word, -2) ->
        word <> "s"

      suffix?(word, "o") ->
        word <> "es"

      true ->
        nil
    end
  end

  defp o_suffix?(word, :classical = mode) do
    cond do
      category?(word, "-o", "-os", mode) ->
        replace_suffix(word, "o", "i")

      suffix?(word, "o") ->
        word <> "es"

      true ->
        nil
    end
  end

  # Handle plurals of compound words (Postmasters General, Major Generals, mothers-in-law, etc) by
  # recursively applying the entire algorithm to the underlying noun. See Table A.26 for the
  # military suffix -general, which inflects to -generals...
  #         if category(-general,-generals), return inflection(-l,-ls)
  #
  #         if the word is of the form: "<word> general",
  #                 return "<plural of word> general"
  #
  #         if the word is of the form: "<word> <preposition> <words>",
  #                 return "<plural of word> <preposition> <words>"

  @generals @inflections
            |> Map.get("a26")

  for general <- @generals do
    defp general?(unquote(general) <> suffix, _mode) do
      if suffix?(suffix, "l"), do: unquote(general) <> suffix <> "s"
    end
  end

  defp general?(_word, _mode) do
    nil
  end

  # Otherwise, assume that the plural just adds -s (cats, programmes, trees, etc.)...
  #         otherwise, return inflection(-,-s)
  defp regular?(word, _mode) do
    word <> "s"
  end

  @doc """
  Pluralize an english verb.

  ### Arguments

  * `word` is any English verb.

  ### Returns

  * a `String` representing the pluralized verb

  ### Examples

      iex> Text.Inflect.En.pluralize_verb "has"
      "have"

      iex> Text.Inflect.En.pluralize_verb "catches"
      "catch"

  """
  def pluralize_verb(word) do
    # All other cases are regular 1st or 2nd person verbs, which don't inflect...
    #         otherwise, return the verb uninflected
    non_inflecting_verb?(word) ||
      irregular_verb?(word) ||
      third_person_singular?(word) ||
      third_person_singular_s?(word) ||
      ambiguous?(word) ||
      word
  end

  defp non_inflecting_verb?(word) do
    if category?(word, "non_inflecting_verb") do
      word
    end
  end

  # Check if the verb is being used as an auxiliary and has a known irregular inflection (has seen,
  # was going, etc. See Table A.8 for irregular verbs)...
  #         if the word has the form "<auxiliary> <words>"
  #         and <auxiliary> belongs to the category of irregular verbs,
  #                 return "<specified plural of auxiliary> <words>"

  # Handle simple irregular verbs (has, is, etc. - see Table A.8)...
  #         if the word belongs to the category of irregular verbs,
  #                 return the specified plural form

  # Combine the both cases in this simpler execution

  defp irregular_verb?(word) do
    if category?(word, "irregular_verb") do
      irregular_verb(word)
    end
  end

  # Verbs in the regular 3rd person singular lose their -es, -ies, or -oes suffix (she catches -
  # they catch, he tries -> they try, it does -> they do, etc.)...
  #         if suffix(-[cs]hes), return inflection(-hes,-h)
  #         if suffix(-[sx]es),  return inflection(-es,-)
  #         if suffix(-zzes),    return inflection(-es,-)
  #         if suffix(-ies),     return inflection(-ies,-y)
  #         if suffix(-oes),     return inflection(-oes,-o)

  defp third_person_singular?(word) do
    cond do
      suffix?(word, "ches") ->
        replace_suffix(word, "hes", "h")

      suffix?(word, "shes") ->
        replace_suffix(word, "hes", "h")

      suffix?(word, "ses") ->
        replace_suffix(word, "es", "")

      suffix?(word, "xes") ->
        replace_suffix(word, "es", "")

      suffix?(word, "zzes") ->
        replace_suffix(word, "es", "")

      suffix?(word, "ies") ->
        replace_suffix(word, "ies", "y")

      suffix?(word, "oes") ->
        replace_suffix(word, "oes", "o")

      true ->
        nil
    end
  end

  # Other 3rd person singular verbs ending in -s (but not -ss) also lose their suffix...
  #         if suffix(-[^s]s), return inflection(-s,-)

  defp third_person_singular_s?(word) do
    cond do
      suffix?(word, "ss") ->
        nil

      suffix?(word, "s") ->
        replace_suffix(word, "s", "")

      true ->
        nil
    end
  end

  # Handle ambiguous simple verbs that might also be nouns (thought, sink, fly, etc. - see Table
  # A.4)...
  #         if the word is in the ambiguous category,
  #                 return the specified plural form

  defp ambiguous?(word) do
    if category?(word, "ambiguous") do
      pluralize_noun(word)
    end
  end

  @doc """
  Pluralize an english adjective.

  ### Arguments

  * `word` is any English adjective.

  ### Returns

  * a `String` representing the pluralized
    adjective

  ### Examples

      iex> Text.Inflect.En.pluralize_adjective "a"
      "some"

      iex> Text.Inflect.En.pluralize_adjective "my"
      "our"

      iex> Text.Inflect.En.pluralize_adjective "child's"
      "children's"

      iex> Text.Inflect.En.pluralize_adjective "Mary's"
      "Marys'"

  """
  def pluralize_adjective(word) do
    # In all other cases no inflection is required...
    #         otherwise, return the adjective uninflected
    indefinite_article?(word) ||
      possessive_pronoun?(word) ||
      genetive?(word) ||
      word
  end

  # Handle indefinite articles and demonstratives...
  #         if the word is "a" or "an", return "some"
  #         if the word is "this",      return "these"
  #         if the word is "that",      return "those"

  def indefinite_article?(word) do
    cond do
      word in ["a", "an"] ->
        "some"

      word == "this" ->
        "these"

      word == "that" ->
        "those"

      true ->
        nil
    end
  end

  # Handle possessive pronouns (my -> our, its -> their, etc - see Table A.7)...
  #         if the word is a personal possessive,
  #                 return the specified plural form

  def possessive_pronoun?(word) do
    if category?(word, "personal_possessive") do
      personal_possessive(word)
    end
  end

  # Handle genitives (dog's -> dogs', child's -> children's, Mary's -> Marys', etc). The general
  # rule is: remove the apostrophe and any trailing -s, form the plural of the resultant noun, and
  # then append an apostrophe (or -'s if the pluralized noun doesn't end in -s)...
  #         if suffix(-'s) or suffix(-'),
  #                 if suffix(-'), let the noun <owner> be inflection(-',-)
  #                 otherwise,     let the noun <owner> be inflection(-'s,-)
  #                 let the noun <owners> be the noun plural of <owner>
  #                 if <owners> ends in -s, return "<owners>'"
  #                 otherwise,              return "<owners>'s"
  def genetive?(word) do
    cond do
      suffix?(word, "'s") -> do_genetive(word, "'s")
      suffix?(word, "'") -> do_genetive(word, "'")
      true -> nil
    end
  end

  def do_genetive(word, suffix) do
    plural_noun =
      word
      |> replace_suffix(suffix, "")
      |> pluralize_noun()

    if suffix?(plural_noun, "s") do
      plural_noun <> "'"
    else
      plural_noun <> "'s"
    end
  end

  ##########################################

  # Category definitions

  ##########################################

  @non_inflecting_nouns @inflections
                        |> Map.take(["a2", "a3"])
                        |> Map.values()
                        |> List.flatten()

  @ambiguous @inflections
             |> Map.get("a4")

  @personal_possessive @inflections
                       |> Map.get("a7")
                       |> Enum.drop(3)
                       |> Enum.flat_map(&String.split(&1, " "))
                       |> Enum.reject(&(&1 == "->" || &1 == " "))
                       |> Enum.chunk_every(2)
                       |> Enum.map(&List.to_tuple/1)
                       |> Map.new()

  @pluralize_auxillary_irregular @inflections
                                 |> Map.get("a8")
                                 |> Enum.drop(3)
                                 |> Enum.map(&String.split(&1, " -> "))
                                 |> Enum.map(&List.to_tuple/1)
                                 |> Map.new()

  @non_inflecting_verbs @inflections
                        |> Map.get("a9")

  @a_ae_modern @inflections
               |> Map.get("a10")

  @a_ae_classical @inflections
                  |> Map.take(["a10", "a11"])
                  |> Map.values()
                  |> List.flatten()

  @a_ata @inflections
         |> Map.get("a12")

  @en_ina @inflections
          |> Map.get("a13")

  @ex_ices_modern @inflections
                  |> Map.get("a14")

  @ex_ices_classical @inflections
                     |> Map.take(["a14", "a15"])
                     |> Map.values()
                     |> List.flatten()

  @is_ides @inflections
           |> Map.get("a16")

  @o_i @inflections
       |> Map.get("a18")

  @o_words_modern @inflections
                  |> Map.take(["a17", "a18"])
                  |> Map.values()
                  |> List.flatten()

  @o_words_classical @inflections
                     |> Map.get("a17")

  @on_a @inflections
        |> Map.get("a19")

  @um_a_modern @inflections
               |> Map.get("a20")

  @um_a_classical @inflections
                  |> Map.take(["a20", "a21"])
                  |> Map.values()
                  |> List.flatten()

  @us_i @inflections
        |> Map.get("a22")

  @us_us @inflections
         |> Map.get("a23")

  @any_i @inflections
         |> Map.get("a24")

  @any_im @inflections
          |> Map.get("a25")

  @pronouns @inflections
            |> Map.get("a5")
            |> Enum.drop(3)
            |> Enum.reject(&(&1 == "->"))
            |> Enum.map(&String.replace(&1, " ->", ""))
            |> Enum.map(fn x ->
              if String.contains?(x, "|"), do: String.split(x, "|"), else: x
            end)
            |> Enum.chunk_every(2)
            |> Map.new(&List.to_tuple/1)

  @irregular @inflections
             |> Map.get("a1")
             |> Enum.chunk_every(3)
             |> Enum.drop(1)
             |> Enum.map(fn
               [word, "(none)", plural] -> {word, [plural, plural]}
               [word, plural, "(none)"] -> {word, [plural, plural]}
               [word, modern, classical] -> {word, [modern, classical]}
               [a, b] -> {a, [b, b]}
             end)
             |> Map.new()

  @doc false
  def category?(word, "irregular_verb") do
    Map.has_key?(@pluralize_auxillary_irregular, word)
  end

  def category?(word, "ambiguous") do
    word in @ambiguous
  end

  def category?(word, "non_inflecting_verb") do
    word in @non_inflecting_verbs
  end

  def category?(word, "personal_possessive") do
    Map.has_key?(@personal_possessive, word)
  end

  @doc false
  def category?(word, "irregular_noun", _mode) do
    Map.has_key?(@irregular, word)
  end

  def category?(word, "pronoun", _mode) do
    Map.has_key?(@pronouns, word)
  end

  @non_inflecting_suffix ["fish", "ois", "sheep", "deer", "pox", "itis"]
  def category?(word, "herd", _mode) do
    Enum.any?(@non_inflecting_suffix, &suffix?(word, &1))
  end

  def category?(word, "nationalities", _mode) do
    suffix?(word, "ese") && starts_with_upper?(word)
  end

  @doc false
  def category?(word, "-", "-", _) do
    word in @non_inflecting_nouns
  end

  def category?(word, "-o", "-os", :classical) do
    word in @o_words_classical
  end

  def category?(word, "-o", "-os", :modern) do
    word in @o_words_modern
  end

  def category?(word, "-ex", "-ices", :modern) do
    word in @ex_ices_modern
  end

  def category?(word, "-ex", "-ices", :classical) do
    word in @ex_ices_classical
  end

  def category?(word, "-um", "-a", :modern) do
    word in @um_a_modern
  end

  def category?(word, "-um", "-a", :classical) do
    word in @um_a_classical
  end

  def category?(word, "-on", "-a", :modern) do
    word in @on_a
  end

  def category?(word, "-on", "-a", :classical) do
    word in @on_a
  end

  def category?(word, "-a", "-ae", :modern) do
    word in @a_ae_modern
  end

  def category?(word, "-a", "-ae", :classical) do
    word in @a_ae_classical
  end

  def category?(word, "-en", "-ina", :classical) do
    word in @en_ina
  end

  def category?(word, "-a", "-ata", _mode) do
    word in @a_ata
  end

  def category?(word, "-is", "-ides", _mode) do
    word in @is_ides
  end

  def category?(word, "-us", "-i", _mode) do
    word in @us_i
  end

  def category?(word, "-us", "-us", _mode) do
    word in @us_us
  end

  def category?(word, "-o", "-i", _mode) do
    word in @o_i
  end

  def category?(word, "-", "-i", _mode) do
    word in @any_i
  end

  def category?(word, "-", "-im", _mode) do
    word in @any_im
  end

  ##########################################

  # Helpers

  ##########################################

  defp suffix?(word, suffix) do
    String.ends_with?(word, suffix)
  end

  defp replace_suffix(word, suffix, replacement) do
    String.replace_suffix(word, suffix, replacement)
  end

  @vowels ["a", "e", "i", "o", "u"]
  defp vowel?(word, pos) do
    String.at(word, pos) in @vowels
  end

  defp irregular_noun(word, mode) do
    [modern, classical] = Map.fetch!(@irregular, word)
    if mode == :modern, do: modern, else: classical
  end

  defp irregular_verb(word) do
    Map.fetch!(@pluralize_auxillary_irregular, word)
  end

  defp pronoun(word, mode) do
    [modern, classical] = Map.fetch!(@pronouns, word)
    if mode == :modern, do: modern, else: classical
  end

  defp personal_possessive(word) do
    Map.fetch!(@personal_possessive, word)
  end

  defp starts_with_upper?(<<char::utf8, _rest::binary>>) when char in ?A..?Z, do: true
  defp starts_with_upper?(_word), do: false
end
