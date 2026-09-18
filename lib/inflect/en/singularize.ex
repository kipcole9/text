defmodule Text.Inflect.En.Singularize do
  @moduledoc false

  import Text.Inflect.En.Helpers
  alias Text.Inflect.En

  @saved_data_path "priv/inflection/en/en.etf"
  @external_resource @saved_data_path

  @inflections File.read!(@saved_data_path)
               |> :erlang.binary_to_term()

  @doc false
  def inflections do
    Text.Inflect.En.Singularize.inflections()
  end

  # Singularize is the INVERSE of this
  # Handle words that do not inflect in the plural (such as fish, travois, chassis, nationalities
  # ending in -ese etc. - see Tables A.2 and A.3)...
  #         if suffix(-fish) or suffix(-ois) or suffix(-sheep)
  #         or suffix(-deer) or suffix(-pox) or suffix(-[A-Z].*ese)
  #         or suffix(-itis) or category(-,-),
  #                 return the original noun

  def non_inflecting?(word, mode) when is_binary(word) do
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

  def pronoun?(word, _mode) do
    pronoun_singular(word)
  end

  # Handle standard irregular plurals (mongooses, oxen, etc. - see table A.1)...
  #         if the word has an irregular plural,
  #                 return the specified singular

  def irregular_noun?(word, mode) do
    irregular_singular(word, mode)
  end

  # Singularize is the INVERSE of this
  # Handle irregular inflections for common suffixes (synopses, mice and men, etc.)...
  #         if suffix(-man),      return inflection(-man,-men)
  #         if suffix(-[lm]ouse), return inflection(-ouse,-ice)
  #         if suffix(-tooth),    return inflection(-tooth,-teeth)
  #         if suffix(-goose),    return inflection(-goose,-geese)
  #         if suffix(-foot),     return inflection(-foot,-feet)
  #         if suffix(-zoon),     return inflection(-zoon,-zoa)
  #         if suffix(-[csx]is),  return inflection(-is,-es)

  def irregular_suffix?(word, _mode) do
    cond do
      suffix?(word, "men") ->
        replace_suffix(word, "men", "man")

      suffix?(word, "lice") ->
        replace_suffix(word, "lice", "louse")

      suffix?(word, "mice") ->
        replace_suffix(word, "mice", "mouse")

      suffix?(word, "teeth") ->
        replace_suffix(word, "teeth", "tooth")

      suffix?(word, "geese") ->
        replace_suffix(word, "geese", "goose")

      suffix?(word, "feet") ->
        replace_suffix(word, "feet", "foot")

      suffix?(word, "zoa") ->
        replace_suffix(word, "zoa", "zoon")

      true ->
        nil
    end
  end

  # Greek/Latin -es/-ces/-xes plurals (analyses → analysis, axes → axis,
  # appendices → appendix). Conservative: only fires when stripping the
  # plural suffix yields a known classical singular.
  @classical_is_es_plurals for(
                             w <- Text.Inflect.En.Helpers.ides_pattern(),
                             String.ends_with?(w, "is"),
                             do: String.replace_suffix(w, "is", "es")
                           )
                           |> MapSet.new()

  def classical_is_plural?(word, _mode) do
    if word in @classical_is_es_plurals do
      String.replace_suffix(word, "es", "is")
    end
  end

  # Singularize is the INVERSE of this
  # Handle fully assimilated classical inflections (vertebrae, codices, etc. - see tables A.10,
  # A.14, A.19 and A.20, and tables A.11, A.15 and A.21 if in "classical mode)...
  #         if category(-ex,-ices), return inflection(-ex,-ices)
  #         if category(-um,-a),    return inflection(-um,-a)
  #         if category(-on,-a),    return inflection(-on,-a)
  #         if category(-a,-ae),    return inflection(-a,-ae)

  def assimilated_classical?(word, mode) do
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

  # Note on ambiguous reversal: singularization is the inverse of pluralization.
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

  def classical?(word, :classical = mode) do
    classical_by_suffix(word) || classical_by_category(word, mode)
  end

  def classical?(word, :modern = mode) do
    if category?(word, "-us", "-i", mode) do
      replace_suffix(word, "us", "uses")
    end
  end

  # Classical rules driven by the raw word suffix.
  defp classical_by_suffix(word) do
    cond do
      suffix?(word, "trices") ->
        replace_suffix(word, "trices", "trix")

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

  # Category-driven classical rules. Actions are `:keep`, `{:replace,
  # from, to}`, or `{:append, chars}`.
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

  # Singularize is the INVERSE of this
  # The suffixes -ch, -sh, and -ss all take -es in the plural (churches, classes, etc)...
  #         if suffix(-[cs]h), return inflection(-h,-hes)
  #         if suffix(-ss),    return inflection(-ss,-sses)

  def compound_plural?(word, _mode) do
    cond do
      suffix?(word, "ches") ->
        replace_suffix(word, "hes", "h")

      suffix?(word, "shes") ->
        replace_suffix(word, "shes", "sh")

      suffix?(word, "sses") ->
        replace_suffix(word, "sses", "ss")

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
  # Certain words ending in -f or -fe take -ves in the plural (lives, wolves, etc)...
  #         if suffix(-[aeo]lf) or suffix(-[^d]eaf) or suffix(-arf),
  #                 return inflection(-f,-ves)
  #
  #         if suffix(-[nlw]ife),
  #                 return inflection(-fe,-ves)

  @ves_to_f_suffixes ~w(alves elves olves arves deaves)
  @ves_to_fe_suffixes ~w(nives lives wives)

  def ves_plural?(word, _mode) do
    cond do
      Enum.any?(@ves_to_f_suffixes, &suffix?(word, &1)) ->
        replace_suffix(word, "ves", "f")

      Enum.any?(@ves_to_fe_suffixes, &suffix?(word, &1)) ->
        replace_suffix(word, "ves", "fe")

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
  # Words ending in -y take -ys if preceded by a vowel (storeys, stays, etc.) or when a proper noun
  # (Marys, Tonys, etc.), but -ies if preceded by a consonant (stories, skies, etc.)...
  #         if suffix(-[aeiou]y), return inflection(-y,-ys)
  #         if suffix(-[A-Z].*y), return inflection(-y,-ys)
  #         if suffix(-y),        return inflection(-y,-ies)

  def word_ending_in_y?(word, _mode) do
    cond do
      suffix?(word, "ys") && vowel?(word, -3) ->
        replace_suffix(word, "ys", "y")

      suffix?(word, "ys") && starts_with_upper?(word) ->
        replace_suffix(word, "ys", "y")

      suffix?(word, "ies") ->
        replace_suffix(word, "ies", "y")

      true ->
        nil
    end
  end

  # TODO
  # Some words ending in -o take -os (lassos, solos, etc. - see tables A.17 and A.18); the rest
  # take -oes (potatoes, dominoes, etc.) However, words in which the -o is preceded by a vowel
  # always take -os (folios, bamboos)...
  #         if category(-o,-os) or suffix(-[aeiou]o),
  #                 return inflection(-o,-os)
  #
  #         if suffix(-o), return inflection(-o,-oes)

  def o_suffix?(word, :modern = mode) do
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

  def o_suffix?(word, :classical = mode) do
    cond do
      category?(word, "-o", "-os", mode) ->
        replace_suffix(word, "o", "i")

      suffix?(word, "o") ->
        word <> "es"

      true ->
        nil
    end
  end

  # Singularize is the INVERSE of this
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
    def general?(unquote(general) <> suffix, _mode) do
      if suffix?(suffix, "ls"), do: unquote(general) <> replace_suffix(suffix, "ls", "l")
    end
  end

  def general?(_word, _mode) do
    nil
  end

  # Non inflecting words don't change in either direction
  def non_inflecting_verb?(word) do
    if category?(word, "non_inflecting_verb") do
      word
    end
  end

  # Singularize is the INVERSE of this
  # Otherwise, assume that the plural just adds -s (cats, programmes, trees, etc.)...
  #         otherwise, return inflection(-,-s)
  #
  # We pattern-match the common English plural suffixes in order of
  # specificity:
  #
  #   * `-ies`  → `-y`     (cities → city)
  #   * `-ves`  → `-fe`    (knives → knife)
  #   * `-shes`/`-ches`/`-sses`/`-zes`/`-xes`/`-oes` → trim `-es`
  #     (boxes → box, kisses → kiss, churches → church, potatoes → potato)
  #   * `-s`    → trim `-s` (cats → cat, houses → house)
  def regular?(word, _mode) do
    if String.length(word) <= 2 do
      word
    else
      regular_singular(word) || word
    end
  end

  defp regular_singular(word) do
    regular_singular_ies_ves_sses(word) ||
      regular_singular_trim_es(word) ||
      regular_singular_trim_s(word)
  end

  # Handle the two dedicated rewrites (-ies → -y, -ves → -fe) and the
  # -sses → -ss trim.
  defp regular_singular_ies_ves_sses(word) do
    cond do
      suffix?(word, "ies") -> replace_suffix(word, "ies", "y")
      suffix?(word, "ves") -> replace_suffix(word, "ves", "fe")
      suffix?(word, "sses") -> replace_suffix(word, "sses", "ss")
      true -> nil
    end
  end

  # Trim -es for -shes/-ches/-xes/-zes, and for -oes when preceded by a
  # consonant (potato, hero). Vowel-preceded -oes (shoes, toes) fall
  # through to the plain -s trim.
  defp regular_singular_trim_es(word) do
    cond do
      suffix?(word, "shes") or suffix?(word, "ches") ->
        replace_suffix(word, "es", "")

      suffix?(word, "xes") or suffix?(word, "zes") ->
        replace_suffix(word, "es", "")

      suffix?(word, "oes") and not vowel?(word, String.length(word) - 4) ->
        replace_suffix(word, "es", "")

      true ->
        nil
    end
  end

  defp regular_singular_trim_s(word) do
    if suffix?(word, "s"), do: replace_suffix(word, "s", "")
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

  def irregular_verb?(word) do
    if category?(word, "irregular_verb") do
      irregular_verb(word)
    end
  end

  # Singularize is the INVERSE of this
  # Verbs in the regular 3rd person singular lose their -es, -ies, or -oes suffix (she catches -
  # they catch, he tries -> they try, it does -> they do, etc.)...
  #         if suffix(-[cs]hes), return inflection(-hes,-h)
  #         if suffix(-[sx]es),  return inflection(-es,-)
  #         if suffix(-zzes),    return inflection(-es,-)
  #         if suffix(-ies),     return inflection(-ies,-y)
  #         if suffix(-oes),     return inflection(-oes,-o)

  # Ordered rules for third_person_singular?/1. Each rule is
  # `{suffix, action}` where action is `:keep`, `{:replace, from, to}`,
  # or `{:append, chars}`. Order matters: `ss` must precede `s`.
  @third_person_rules [
    {"ch", {:replace, "ch", "ches"}},
    {"sh", {:replace, "sh", "shes"}},
    {"ss", :keep},
    {"s", {:append, "ses"}},
    {"x", {:append, "xes"}},
    {"zz", {:replace, "zz", "zzes"}},
    {"y", {:replace, "y", "ies"}},
    {"o", {:replace, "o", "oes"}}
  ]

  def third_person_singular?(word) do
    Enum.find_value(@third_person_rules, fn {suffix, action} ->
      if suffix?(word, suffix), do: apply_third_person_action(word, action)
    end)
  end

  defp apply_third_person_action(word, :keep), do: word
  defp apply_third_person_action(word, {:replace, from, to}), do: replace_suffix(word, from, to)
  defp apply_third_person_action(word, {:append, chars}), do: word <> chars

  # Singularize is the INVERSE of this
  # NOTE that this is implemented in third_person_singular?/1 above
  # Other 3rd person singular verbs ending in -s (but not -ss) also lose their suffix...
  #         if suffix(-[^s]s), return inflection(-s,-)

  def third_person_singular_s?(_word) do
    nil
  end

  # Handle ambiguous simple verbs that might also be nouns (thought, sink, fly, etc. - see Table
  # A.4)...
  #         if the word is in the ambiguous category,
  #                 return the specified plural form

  def ambiguous?(word) do
    if category?(word, "ambiguous") do
      En.pluralize_noun(word)
    end
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
      suffix?(word, "'s") ->
        do_genetive(word, "'s")

      suffix?(word, "'") ->
        do_genetive(word, "'")

      true ->
        nil
    end
  end

  def do_genetive(word, suffix) do
    plural_noun =
      word
      |> replace_suffix(suffix, "")
      |> En.pluralize_noun()

    if suffix?(plural_noun, "s") do
      plural_noun <> "'"
    else
      plural_noun <> "'s"
    end
  end

  @doc false
  def category?(word, "irregular_verb") do
    Map.has_key?(pluralize_auxillary_irregular(), word)
  end

  def category?(word, "ambiguous") do
    word in ambiguous()
  end

  def category?(word, "non_inflecting_verb") do
    word in non_inflecting_verbs()
  end

  def category?(word, "personal_possessive") do
    Map.has_key?(personal_possessive(), word)
  end

  @doc false
  def category?(word, "irregular_noun", _mode) do
    Map.has_key?(irregular(), word)
  end

  def category?(word, "pronoun", _mode) do
    Map.has_key?(pronouns(), word)
  end

  def category?(word, "herd", _mode) do
    Enum.any?(non_inflecting_suffix(), &suffix?(word, &1))
  end

  def category?(word, "nationalities", _mode) do
    suffix?(word, "ese") && starts_with_upper?(word)
  end

  @doc false
  def category?(word, "-", "-", _) do
    word in non_inflecting_nouns()
  end

  def category?(word, "-o", "-os", :classical) do
    word in o_words_classical()
  end

  def category?(word, "-o", "-os", :modern) do
    word in o_words_modern()
  end

  def category?(word, "-ex", "-ices", :modern) do
    word in ex_ices_modern()
  end

  def category?(word, "-ex", "-ices", :classical) do
    word in ex_ices_classical()
  end

  def category?(word, "-um", "-a", :modern) do
    word in um_a_modern()
  end

  def category?(word, "-um", "-a", :classical) do
    word in um_a_classical()
  end

  def category?(word, "-on", "-a", _mode) do
    word in on_a()
  end

  def category?(word, "-a", "-ae", :modern) do
    word in a_ae_modern()
  end

  def category?(word, "-a", "-ae", :classical) do
    word in a_ae_classical()
  end

  def category?(word, "-en", "-ina", :classical) do
    word in en_ina()
  end

  def category?(word, "-a", "-ata", _mode) do
    word in a_ata()
  end

  def category?(word, "-is", "-ides", _mode) do
    word in ides_pattern()
  end

  def category?(word, "-us", "-i", _mode) do
    word in us_i()
  end

  def category?(word, "-us", "-us", _mode) do
    word in us_us()
  end

  def category?(word, "-o", "-i", _mode) do
    word in o_i()
  end

  def category?(word, "-", "-i", _mode) do
    word in any_i()
  end

  def category?(word, "-", "-im", _mode) do
    word in any_im()
  end
end
