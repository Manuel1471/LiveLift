defmodule LiveLift.Template do
  @moduledoc "Parses client templates into a validated tree shared by both runtimes."

  alias LiveLift.Template.Expression
  alias Phoenix.LiveView.TagEngine.Parser

  @dynamic_attributes ~w(class title aria-label value)
  @events ~w($click $server $input $change $submit)
  @void_tags ~w(area base br col embed hr img input link meta param source track wbr)

  @spec compile(String.t(), String.t()) :: list(map())
  def compile(source, file \\ "nofile") when is_binary(source) do
    source
    |> Parser.parse!(tag_handler: Phoenix.LiveView.HTMLEngine, file: file)
    |> Map.fetch!(:nodes)
    |> Enum.map(&convert_node(&1, file))
  rescue
    error in Phoenix.LiveView.TagEngine.Tokenizer.ParseError ->
      raise ArgumentError, Exception.message(error)
  end

  @spec render_server(list(map()), map()) :: Phoenix.HTML.safe()
  def render_server(tree, state) when is_list(tree) and is_map(state) do
    tree |> render_nodes(%{"state" => state}) |> Phoenix.HTML.raw()
  end

  defp convert_node({:text, text, _meta}, _file), do: %{type: "text", value: text}

  defp convert_node({:body_expr, source, meta}, file),
    do: %{type: "binding", expr: Expression.parse(source, file, meta.line)}

  defp convert_node({:block, type, tag, attrs, children, meta, _close}, file),
    do: convert_element(type, tag, attrs, children, meta, file)

  defp convert_node({:self_close, type, tag, attrs, meta}, file),
    do: convert_element(type, tag, attrs, [], meta, file)

  defp convert_node(other, file),
    do: raise(ArgumentError, "#{file}: unsupported client template node: #{inspect(other)}")

  defp convert_element(type, tag, attrs, children, meta, file) do
    unless type == :tag do
      raise ArgumentError, "#{file}:#{meta.line}: client components are not supported yet: #{tag}"
    end

    parsed_attrs = Enum.map(attrs, &convert_attr(&1, file))
    names = Enum.map(parsed_attrs, & &1.name)

    if length(names) != length(Enum.uniq(names)) do
      raise ArgumentError, "#{file}:#{meta.line}: duplicate client attribute on <#{tag}>"
    end

    %{
      type: "element",
      tag: tag,
      attrs: parsed_attrs,
      children: Enum.map(children, &convert_node(&1, file)),
      void: tag in @void_tags,
      line: meta.line
    }
  end

  defp convert_attr({name, {:string, value, _}, meta}, file) do
    cond do
      name in @events and Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, value) ->
        target =
          if name == "$click",
            do: "data-live-lift-action",
            else: String.replace_prefix(name, "$", "data-live-lift-")

        %{name: target, value: value, type: "static"}

      name == "$show" and Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, value) ->
        %{name: "data-live-lift-show", value: value, type: "static"}

      String.starts_with?(name, ["$", ":"]) ->
        raise ArgumentError, "#{file}:#{meta.line}: unsupported client directive: #{name}"

      String.contains?(value, "{@") ->
        if name in @dynamic_attributes and Regex.match?(~r/^\{@[^}]+\}$/, value) do
          expression =
            value |> String.slice(1, byte_size(value) - 2) |> Expression.parse(file, meta.line)

          %{name: name, value: expression, type: "dynamic"}
        else
          raise ArgumentError,
                "#{file}:#{meta.line}: unsupported client template attribute interpolation: #{name}"
        end

      true ->
        %{name: name, value: value, type: "static"}
    end
  end

  defp convert_attr({name, {:expr, source, meta}, _attr_meta}, file),
    do:
      raise(
        ArgumentError,
        "#{file}:#{meta.line}: unsupported client expression attribute: #{name}={#{source}}"
      )

  defp render_nodes(nodes, scope), do: Enum.map_join(nodes, "", &render_node(&1, scope))
  defp render_node(%{type: "text", value: value}, _scope), do: value

  defp render_node(%{type: "binding", expr: expr}, scope) do
    value = expr |> Expression.eval(scope) |> display_value() |> escape()
    "<span data-live-lift-text=\"#{path_label(expr)}\">#{value}</span>"
  end

  defp render_node(%{type: "element"} = node, scope) do
    attrs = Enum.map_join(node.attrs, "", &render_attr(&1, scope))
    attrs = if hidden?(node.attrs, scope), do: attrs <> " hidden", else: attrs
    opening = "<#{node.tag}#{attrs}>"

    if node.void,
      do: opening,
      else: opening <> render_nodes(node.children, scope) <> "</#{node.tag}>"
  end

  defp render_attr(%{name: "data-live-lift-show", value: value}, _scope),
    do: " data-live-lift-show=\"#{value}\""

  defp render_attr(%{name: name, type: "static", value: value}, _scope),
    do: " #{name}=\"#{value}\""

  defp render_attr(%{name: name, type: "dynamic", value: expr}, scope) do
    value = expr |> Expression.eval(scope) |> display_value() |> escape()
    " #{name}=\"#{value}\" data-live-lift-bind-#{name}=\"#{path_label(expr)}\""
  end

  defp hidden?(attrs, scope) do
    Enum.any?(attrs, fn
      %{name: "data-live-lift-show", value: field} ->
        Expression.eval(%{type: "path", root: "state", fields: [field]}, scope) in [false, nil]

      _ ->
        false
    end)
  end

  defp path_label(%{type: "path", root: "state", fields: fields}), do: Enum.join(fields, ".")

  defp path_label(%{type: "path", root: root, fields: fields}),
    do: Enum.join([root | fields], ".")

  defp path_label(_), do: "expression"

  defp display_value(nil), do: ""

  defp display_value(value) when is_binary(value) or is_number(value) or is_boolean(value),
    do: to_string(value)

  defp display_value(value),
    do: raise(ArgumentError, "cannot display client value: #{inspect(value)}")

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
