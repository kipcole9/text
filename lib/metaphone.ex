defmodule Text.Metaphone do
  @moduledoc """
  The original Metaphone algorithm was published in 1990 as an improvement over
  the Soundex algorithm. Like Soundex, it was limited to English-only use. The
  Metaphone algorithm does not produce phonetic representations of an input word
  or name; rather, the output is an intentionally approximate phonetic
  representation. The approximate encoding is necessary to account for the way
  speakers vary their pronunciations and misspell or otherwise vary words and
  names they are trying to spell.

  The Double Metaphone phonetic encoding algorithm is the second generation of
  the Metaphone algorithm. Its implementation was described in the June 2000
  issue of C/C++ Users Journal. It makes a number of fundamental design
  improvements over the original Metaphone algorithm.

  It is called "Double" because it can return both a primary and a secondary code
  for a string; this accounts for some ambiguous cases as well as for multiple
  variants of surnames with common ancestry. For example, encoding the name
  "Smith" yields a primary code of SM0 and a secondary code of XMT, while the
  name "Schmidt" yields a primary code of XMT and a secondary code of SMT--both
  have XMT in common.

  Double Metaphone tries to account for myriad irregularities in English of
  Slavic, Germanic, Celtic, Greek, French, Italian, Spanish, Chinese, and other
  origin. Thus it uses a much more complex ruleset for coding than its
  predecessor; for example, it tests for approximately 100 different contexts of
  the use of the letter C alone.

  This script implements the Double Metaphone algorithm (c) 1998, 1999 originally
  implemented by Lawrence Philips in C++. It was further modified in C++ by Kevin
  Atkinson (http://aspell.net/metaphone/). It was translated to C by Maurice
  Aubrey <maurice@hevanet.com> for use in a Perl extension. A Python version was
  created by Andrew Collins on January 12, 2007, using the C source
  (http://www.atomodo.com/code/double-metaphone/metaphone.py/view).

  """
  @silent_starters ["gn", "kn", "pn", "wr", "ps"]
  @vowels ["a", "e", "i", "o", "u"]

  # The parameter structure is:
  # consumed:  The characters in the string we have already processed
  # string: the string we are now processing
  # m1, m2: The metaphone codes we are accumulating

  # Ignore silent starters
  def metaphone("", << start :: binary-2, rest :: binary >>, "" = m1, "" = m2)
      when start in @silent_starters do
    metaphone(start, rest, m1, m2)
  end

  # Initial "Z" maps to an "S"
  def metaphone("", << "z", rest :: binary >>, "" = m1, "" = m2) do
    metaphone("", "s" <> rest, m1, m2)
  end

  # Initial vowel maps to "A"
  def metaphone("", << vowel :: binary-1, rest :: binary >>, "", "")
      when vowel in @vowels do
    metaphone(vowel, rest, "a", "a")
  end

  def metaphone(consumed, << "bb", rest :: binary >>, m1, m2) do
    metaphone(consumed <> "bb", rest, m1 <> "p", m2 <> "p")
  end

  def metaphone(consumed, << "b", rest :: binary >>, m1, m2) do
    metaphone(consumed <> "b", rest, m1 <> "p", m2 <> "p")
  end


end