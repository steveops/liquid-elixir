defmodule Liquid.Variable do
  @moduledoc """
    Module to create and lookup for Variables

  """
  defstruct name: nil, literal: nil, filters: [], parts: []
  alias Liquid.{Appointer, Filters, Variable, Context}

  @doc """
    resolves data from `Liquid.Variable.parse/1` and creates a variable struct
  """
  def create(markup) when is_binary(markup) do
    [name | filters] = markup |> parse
    name = String.trim(name)
    variable = %Liquid.Variable{name: name, filters: filters}
    parsed = Liquid.Appointer.parse_name(name)

    if String.contains?(name, "%") do
      raise Liquid.SyntaxError, message: "Invalid variable name"
    end

    Map.merge(variable, parsed)
  end

  @doc """
  Assigns context to variable and than applies all filters
  """
  @spec lookup(%Variable{}, %Context{}) :: {String.t(), %Context{}}
  def lookup(%Variable{} = v, %Context{} = context) do
    {ret, filters} = Appointer.assign(v, context)

    ret = maybe_escape_variable(ret, context)

    result =
      try do
        {:ok, filters |> Filters.filter(ret) |> apply_global_filter(context)}
      rescue
        e in UndefinedFunctionError -> {e, e.reason}
        e in ArgumentError -> {e, e.message}
        e in ArithmeticError -> {e, "Liquid error: #{e.message}"}
      end

    case result do
      {:ok, text} -> {text, context}
      {error, message} -> process_error(context, error, message)
    end
  end

  defp maybe_escape_variable(rendered, %Context{escape_variables: true}), do: escape(rendered)
  defp maybe_escape_variable(rendered, _), do: rendered

  defp escape(data) when is_binary(data),
       do: escape(data, "")

  defp escape(not_binary), do: not_binary

  defp escape(<<0x2028::utf8, t::binary>>, acc),
       do: escape(t, <<acc::binary, "\\u2028">>)

  defp escape(<<0x2029::utf8, t::binary>>, acc),
       do: escape(t, <<acc::binary, "\\u2029">>)

  defp escape(<<0::utf8, t::binary>>, acc),
       do: escape(t, <<acc::binary, "\\u0000">>)

  defp escape(<<"</", t::binary>>, acc),
       do: escape(t, <<acc::binary, ?<, ?\\, ?/>>)

  defp escape(<<"\t", t::binary>>, acc),
       do: escape(t, <<acc::binary, ?\\, ?t>>)

  defp escape(<<"\n", t::binary>>, acc),
       do: escape(t, <<acc::binary, ?\\, ?n>>)

  defp escape(<<"\r\n", t::binary>>, acc),
       do: escape(t, <<acc::binary, ?\\, ?n>>)

  defp escape(<<h, t::binary>>, acc) when h in [?", ?\\],
       do: escape(t, <<acc::binary, ?\\, h>>)

  defp escape(<<h, t::binary>>, acc) when h in [?\r, ?\n],
       do: escape(t, <<acc::binary, ?\\, ?n>>)

  defp escape(<<h, t::binary>>, acc),
       do: escape(t, <<acc::binary, h>>)

  defp escape(<<>>, acc), do: acc

  defp process_error(%Context{template: template} = context, error, message) do
    error_mode = Application.get_env(:liquid, :error_mode, :lax)

    case error_mode do
      :lax ->
        {message, context}

      :strict ->
        context = %{context | template: %{template | errors: template.errors ++ [error]}}
        {nil, context}
    end
  end

  defp apply_global_filter(input, %Context{global_filter: nil}), do: input

  defp apply_global_filter(input, %Context{global_filter: global_filter}),
    do: global_filter.(input)

  @doc """
  Parses the markup to a list of filters
  """
  def parse(markup) when is_binary(markup) do
    parsed_variable =
      if markup != "" do
        Liquid.filter_parser()
        |> Regex.scan(markup)
        |> List.flatten()
        |> Enum.map(&String.trim/1)
      else
        [""]
      end

    if hd(parsed_variable) == "|" or hd(Enum.reverse(parsed_variable)) == "|" do
      raise Liquid.SyntaxError, message: "You cannot use an empty filter"
    end

    [name | filters] = Enum.filter(parsed_variable, &(&1 != "|"))

    filters = parse_filters(filters)
    [name | filters]
  end

  defp parse_filters(filters) do
    for markup <- filters do
      [_, filter] = ~r/\s*(\w+)/ |> Regex.scan(markup) |> hd()

      args =
        Liquid.filter_arguments()
        |> Regex.scan(markup)
        |> List.flatten()
        |> Liquid.List.even_elements()

      [String.to_atom(filter), args]
    end
  end
end
