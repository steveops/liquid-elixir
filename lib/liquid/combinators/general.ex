defmodule Liquid.Combinators.General do
  @moduledoc """
  General purpose combinators used by almost every other combinator
  """
  import NimbleParsec
  alias Liquid.Combinators.LexicalToken

  @type comparison_operators :: :== | :!= | :> | :< | :>= | :<= | :contains
  @type conditions :: [
          condition:
            {LexicalToken.value(), comparison_operators(), LexicalToken.value()}
            | [logical: [and: General.condition()]]
            | [logical: [or: General.condition()]]
        ]
  @type liquid_variable :: [liquid_variable: LexicalToken.variable_value(), filters: [filter()]]
  @type filter :: [filter: String.t(), params: [value: LexicalToken.value()]]

  # Codepoints
  @horizontal_tab 0x0009
  @space 0x0020
  @colon 0x003A
  @point 0x002E
  @newline 0x000A
  @carriage_return 0x000D
  @comma 0x002C
  @single_quote 0x0027
  @double_quote 0x0022
  @question_mark 0x003F
  @underscore 0x005F
  @dash 0x002D
  @equal 0x003D
  @vertical_line 0x007C
  @rigth_curly_bracket 0x007D
  @start_tag "{%"
  @end_tag "%}"
  @start_variable "{{"
  @end_variable "}}"
  @start_filter "|"
  @equals "=="
  @does_not_equal "!="
  @greater_than ">"
  @less_than "<"
  @greater_or_equal ">="
  @less_or_equal "<="
  @digit ?0..?9
  @uppercase_letter ?A..?Z
  @lowercase_letter ?a..?z

  def codepoints do
    %{
      horizontal_tab: @horizontal_tab,
      space: @space,
      colon: @colon,
      point: @point,
      carriage_return: @carriage_return,
      newline: @newline,
      comma: @comma,
      equal: @equal,
      vertical_line: @vertical_line,
      right_curly_bracket: @rigth_curly_bracket,
      quote: @double_quote,
      single_quote: @single_quote,
      question_mark: @question_mark,
      underscore: @underscore,
      start_tag: @start_tag,
      end_tag: @end_tag,
      start_variable: @start_variable,
      end_variable: @end_variable,
      start_filter: @start_filter,
      digit: @digit,
      uppercase_letter: @uppercase_letter,
      lowercase_letter: @lowercase_letter
    }
  end

  @doc """
  Horizontal Tab (U+0009) +
  Space (U+0020) +
  Carriage Return (U+000D)
  New Line (U+000A)
  """
  def whitespace do
    ascii_char([
      @horizontal_tab,
      @carriage_return,
      @newline,
      @space
    ])
  end

  @doc """
  Remove all :whitespace
  """
  def ignore_whitespaces do
    whitespace()
    |> repeat()
    |> ignore()
  end

  @doc """
  Comma without spaces
  """
  def cleaned_comma do
    ignore_whitespaces()
    |> concat(ascii_char([@comma]))
    |> concat(ignore_whitespaces())
    |> ignore()
  end

  @doc """
  Start of liquid Tag
  """
  def start_tag do
    empty()
    |> string(@start_tag)
    |> concat(ignore_whitespaces())
    |> ignore()
  end

  @doc """
  End of liquid Tag
  """
  def end_tag do
    ignore_whitespaces()
    |> concat(string(@end_tag))
    |> ignore()
  end

  @doc """
  Start of liquid Variable
  """
  def start_variable do
    empty()
    |> string(@start_variable)
    |> concat(ignore_whitespaces())
    |> ignore()
  end

  @doc """
  End of liquid Variable
  """
  def end_variable do
    ignore_whitespaces()
    |> string(@end_variable)
    |> ignore()
  end

  @doc """
  Comparison operators:
  == != > < >= <=
  """
  def comparison_operators do
    empty()
    |> choice([
      string(@equals),
      string(@greater_or_equal),
      string(@less_or_equal),
      string(@does_not_equal),
      string(@greater_than),
      string(@less_than),
      string("contains")
    ])
    |> map({String, :to_atom, []})
  end

  @doc """
  Logical operators:
  `and` `or`
  """
  def logical_operators do
    empty()
    |> choice([
      string("or"),
      string("and"),
      string(",") |> replace("or")
    ])
    |> map({String, :to_atom, []})
  end

  def condition do
    empty()
    |> parsec(:value_definition)
    |> parsec(:comparison_operators)
    |> parsec(:value_definition)
    |> reduce({List, :to_tuple, []})
    |> unwrap_and_tag(:condition)
  end

  def logical_condition do
    logical_operators()
    |> choice([parsec(:condition), parsec(:value_definition)])
    |> tag(:logical)
  end

  @doc """
  All utf8 valid characters or empty limited by start of tag
  """
  def literal_until_tag do
    empty()
    |> repeat_until(utf8_char([]), [string(@start_tag)])
    |> reduce({List, :to_string, []})
  end

  defp allowed_chars do
    [
      @digit,
      @uppercase_letter,
      @lowercase_letter,
      @underscore,
      @dash
    ]
  end

  @doc """
  Valid variable definition represented by:
  start char [A..Z, a..z, _] plus optional n times [A..Z, a..z, 0..9, _, -]
  """
  def variable_definition_for_assignment do
    empty()
    |> concat(ignore_whitespaces())
    |> utf8_char([@uppercase_letter, @lowercase_letter, @underscore])
    |> optional(times(utf8_char(allowed_chars()), min: 1))
    |> concat(ignore_whitespaces())
    |> reduce({List, :to_string, []})
  end

  def variable_name_for_assignment do
    parsec(:variable_definition_for_assignment)
    |> tag(:variable_name)
  end

  def variable_definition do
    empty()
    |> parsec(:variable_definition_for_assignment)
    |> optional(utf8_char([@question_mark]))
    |> concat(ignore_whitespaces())
    |> reduce({List, :to_string, []})
  end

  @doc """
  Valid variable name which is a tagged variable_definition
  """
  def variable_name do
    parsec(:variable_definition)
    |> unwrap_and_tag(:variable_name)
  end

  def quoted_variable_name do
    ignore_whitespaces()
    |> ignore(utf8_char([@single_quote]))
    |> parsec(:variable_definition)
    |> ignore(utf8_char([@single_quote]))
    |> concat(ignore_whitespaces())
    |> unwrap_and_tag(:variable_name)
  end

  def not_empty_liquid_variable do
    start_variable()
    |> parsec(:value_definition)
    |> optional(times(parsec(:filters), min: 1))
    |> concat(end_variable())
    |> tag(:liquid_variable)
  end

  def empty_liquid_variable do
    start_variable()
    |> string("")
    |> concat(end_variable())
    |> tag(:liquid_variable)
  end

  def liquid_variable do
    empty()
    |> choice([empty_liquid_variable(), not_empty_liquid_variable()])
  end

  def single_quoted_token do
    ignore_whitespaces()
    |> concat(utf8_char([@single_quote]))
    |> concat(repeat(utf8_char(not: @comma, not: @single_quote)))
    |> concat(utf8_char([@single_quote]))
    |> reduce({List, :to_string, []})
    |> concat(ignore_whitespaces())
  end

  def double_quoted_token do
    ignore_whitespaces()
    |> concat(utf8_char([@double_quote]))
    |> concat(repeat(utf8_char(not: @comma, not: @double_quote)))
    |> concat(utf8_char([@double_quote]))
    |> reduce({List, :to_string, []})
    |> concat(ignore_whitespaces())
  end

  def quoted_token do
    choice([double_quoted_token(), single_quoted_token()])
  end

  @doc """
  Filter basic structure, it acepts any kind of filter with the following structure:
  start char: '|' plus filter's parameters as optional: ':' plus optional: parameters values [value]
  """
  def filter_param do
    empty()
    |> optional(ignore(utf8_char([@colon])))
    |> concat(ignore_whitespaces())
    |> parsec(:value)
    |> optional(ignore(utf8_char([@comma])))
    |> optional(ignore_whitespaces())
    |> optional(parsec(:value))
    |> tag(:params)
  end

  def filters do
    filter()
    |> times(min: 1)
    |> tag(:filters)
  end

  @doc """
  Filter parameters structure:  it acepts any kind of parameters with the following structure:
  start char: ':' plus optional: parameters values [value]
  """
  def filter do
    ignore_whitespaces()
    |> ignore(string(@start_filter))
    |> concat(ignore_whitespaces())
    |> utf8_string(
      [not: @colon, not: @vertical_line, not: @rigth_curly_bracket, not: @space],
      min: 1
    )
    |> concat(ignore_whitespaces())
    |> reduce({List, :to_string, []})
    |> optional(filter_param())
    |> tag(:filter)
    |> optional(parsec(:filter))
  end

  @doc """
  Parse and ignore an assign symbol
  """
  def assignment(symbol) do
    empty()
    |> optional(cleaned_comma())
    |> parsec(:variable_name)
    |> ignore(utf8_char([symbol]))
    |> parsec(:value)
  end

  def tag_param(name) do
    empty()
    |> concat(ignore_whitespaces())
    |> ignore(string(name))
    |> ignore(ascii_char([@colon]))
    |> concat(ignore_whitespaces())
    |> choice([parsec(:number), parsec(:variable_definition)])
    |> concat(ignore_whitespaces())
    |> tag(String.to_atom(name))
  end

  def conditions(combinator) do
    combinator
    |> choice([
      parsec(:condition),
      parsec(:value_definition),
      parsec(:variable_definition)
    ])
    |> optional(times(parsec(:logical_condition), min: 1))
    |> tag(:conditions)
  end

  @doc """
  Parses a `Liquid` tag name, isolates tag name from markup. It represents the tag name parsed
  until end tag `%}`
  """
  @spec valid_tag_name() :: NimbleParsec.t()
  def valid_tag_name do
    empty()
    |> repeat_until(utf8_char([]), [
      string(" "),
      string("%}"),
      ascii_char([
        @horizontal_tab,
        @carriage_return,
        @newline,
        @space
      ])
    ])
    |> reduce({List, :to_string, []})
  end
end