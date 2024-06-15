defmodule Liquid.Render do
  alias Liquid.Variable
  alias Liquid.Template
  alias Liquid.Registers
  alias Liquid.Context
  alias Liquid.Block
  alias Liquid.Tag

  def render(%Template{root: root}, %Context{} = context) do
    {output, context} = render([], root, context)
    {:ok, output |> to_text, context}
  end

  def render(output, [], %Context{} = context) do
    {output, context}
  end

  def render(output, [h | t], %Context{} = context) do
    {output, context} = render(output, h, context)

    case context do
      %Context{extended: false, break: false, continue: false} -> render(output, t, context)
      _ -> render(output, [], context)
    end
  end

  def render(output, text, %Context{} = context) when is_binary(text) do
    {[text | output], context}
  end

  def render(output, %Variable{} = variable, %Context{} = context) do
    {rendered, context} = Variable.lookup(variable, context)
    rendered = maybe_escape_variable(rendered, context)
    {[join_list(rendered) | output], context}
  end

  def render(output, %Tag{name: name} = tag, %Context{} = context) do
    {mod, Tag} = Registers.lookup(name)
    mod.render(output, tag, context)
  end

  def render(output, %Block{name: name} = block, %Context{} = context) do
    case Registers.lookup(name) do
      {mod, Block} -> mod.render(output, block, context)
      nil -> render(output, block.nodelist, context)
    end
  end

  def to_text(list), do: list |> List.flatten() |> Enum.reverse() |> Enum.join()

  defp join_list(input) when is_list(input), do: input |> List.flatten() |> Enum.join()

  defp join_list(input), do: input

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

  defp escape(<<h, t::binary>>, acc) when h in [?", ?\\, ?`],
       do: escape(t, <<acc::binary, ?\\, h>>)

  defp escape(<<h, t::binary>>, acc) when h in [?\r, ?\n],
       do: escape(t, <<acc::binary, ?\\, ?n>>)

  defp escape(<<h, t::binary>>, acc),
       do: escape(t, <<acc::binary, h>>)

  defp escape(<<>>, acc), do: acc
end
