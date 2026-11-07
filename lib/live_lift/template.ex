defmodule LiveLift.Template do
  @moduledoc "Parses client templates into a validated tree shared by both runtimes."

  alias LiveLift.Template.Expression
  alias LiveLift.Template.Parser

  @dynamic_attributes ~w(class title aria-label value)
  @events ~w($click $server $input $change $submit)
  @void_tags ~w(area base br col embed hr img input link meta param source track wbr)
  @forbidden_tags ~w(script iframe object embed)

  @spec compile(String.t(), String.t()) :: list(map())
  def compile(source, file \\ "nofile") when is_binary(source) do
    source |> Parser.parse!(file) |> Enum.map(&convert_node(&1, file))
  end

  @doc false
  def compile_liveview(source, file, client_events) when is_binary(source) do
    source
    |> Parser.parse!(file)
    |> Enum.map(&adapt_liveview_node(&1, file, client_events))
    |> Enum.map(&convert_node(&1, file))
  end

  defp adapt_liveview_node({:block, type, tag, attrs, children, meta, close}, file, events) do
    if tag == "form" and marked_event?(attrs, events) do
      validate_flat_form!(children, file, meta.line)
    end

    {:block, type, tag, adapt_liveview_attrs(attrs, file, events),
     Enum.map(children, &adapt_liveview_node(&1, file, events)), meta, close}
  end

  defp adapt_liveview_node({:self_close, type, tag, attrs, meta}, file, events) do
    validate_change_control!(tag, attrs, file, meta.line, events)
    {:self_close, type, tag, adapt_liveview_attrs(attrs, file, events), meta}
  end

  defp adapt_liveview_node(node, _file, _events), do: node

  defp marked_event?(attrs, events) do
    Enum.any?(attrs, fn
      {name, {:string, event, _}, _} when name in ~w(phx-change phx-submit) ->
        event in events

      _ ->
        false
    end)
  end

  defp validate_change_control!("input", attrs, file, line, events) do
    if Enum.any?(attrs, fn
         {"phx-change", {:string, event, _}, _} -> event in events
         _ -> false
       end) do
      type =
        Enum.find_value(attrs, fn
          {"type", {:string, value, _}, _} -> value
          _ -> nil
        end)

      if type in ~w(checkbox radio file) do
        raise ArgumentError,
              "#{file}:#{line}: @client phx-change does not support #{type} inputs yet; keep this event on the server"
      end
    end
  end

  defp validate_change_control!(_tag, _attrs, _file, _line, _events), do: :ok

  defp validate_flat_form!(children, file, line) do
    names = flat_form_names(children)

    if unsupported_form_control?(children) do
      raise ArgumentError,
            "#{file}:#{line}: @client form has a checkbox, radio, file or multiple-select control; keep this event on the server"
    end

    for name <- names do
      unless Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name) and
               name not in ~w(__proto__ constructor prototype _live_lift_seq) do
        raise ArgumentError,
              "#{file}:#{line}: @client form requires flat safe input names; move nested forms to a server handler"
      end
    end

    if length(names) != length(Enum.uniq(names)) do
      raise ArgumentError,
            "#{file}:#{line}: @client form has duplicate input names; move this event to a server handler"
    end
  end

  defp flat_form_names(nodes) do
    Enum.flat_map(nodes, fn
      {:block, :tag, _tag, attrs, children, _, _} -> form_name(attrs) ++ flat_form_names(children)
      {:self_close, :tag, _tag, attrs, _} -> form_name(attrs)
      _ -> []
    end)
  end

  defp unsupported_form_control?(nodes) do
    Enum.any?(nodes, fn
      {:block, :tag, tag, attrs, children, _, _} ->
        unsupported_control?(tag, attrs) or unsupported_form_control?(children)

      {:self_close, :tag, tag, attrs, _} ->
        unsupported_control?(tag, attrs)

      _ ->
        false
    end)
  end

  defp unsupported_control?("input", attrs) do
    Enum.any?(attrs, fn
      {"type", {:string, type, _}, _} -> type in ~w(checkbox radio file)
      _ -> false
    end)
  end

  defp unsupported_control?("select", attrs),
    do: Enum.any?(attrs, fn {name, _, _} -> name == "multiple" end)

  defp unsupported_control?(_tag, _attrs), do: false

  defp form_name(attrs) do
    Enum.flat_map(attrs, fn
      {"name", {:string, value, _}, _} -> [value]
      _ -> []
    end)
  end

  defp adapt_liveview_attrs(attrs, file, events) do
    Enum.flat_map(attrs, fn
      {"phx-target", {:expr, "@myself", _}, _} ->
        []

      {"phx-target", _, meta} ->
        raise ArgumentError,
              "#{file}:#{meta.line}: @client supports phx-target={@myself}; move other targets to a server handler"

      {event_attr, {:string, event, _} = value, meta} = attr
      when event_attr in ~w(phx-click phx-change phx-submit) ->
        if event in events do
          directive =
            case event_attr do
              "phx-click" -> "$click"
              "phx-change" -> "$change"
              "phx-submit" -> "$submit"
            end

          [attr, {directive, value, meta}]
        else
          [attr]
        end

      attr ->
        [attr]
    end)
  end

  @spec render_server(list(map()), map()) :: Phoenix.HTML.safe()
  def render_server(tree, state) when is_list(tree) and is_map(state) do
    tree |> render_nodes(%{"state" => state}, []) |> Phoenix.HTML.raw()
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

  defp convert_element(:remote_component, tag, attrs, children, meta, file) do
    unless children == [] do
      raise ArgumentError, "#{file}:#{meta.line}: client components do not accept children"
    end

    props =
      Enum.map(attrs, fn
        {name, {:expr, source, expression_meta}, _} when is_binary(name) ->
          %{name: name, expr: Expression.parse(source, file, expression_meta.line)}

        {name, _, _} ->
          raise ArgumentError,
                "#{file}:#{meta.line}: client component prop #{name} requires an Elixir expression"
      end)

    %{type: "component", module: tag, props: props, line: meta.line}
  end

  defp convert_element(type, tag, attrs, children, meta, file) do
    unless type == :tag do
      raise ArgumentError, "#{file}:#{meta.line}: client components are not supported yet: #{tag}"
    end

    if tag in @forbidden_tags do
      raise ArgumentError, "#{file}:#{meta.line}: unsafe client template tag: #{tag}"
    end

    directive = fn name -> Enum.find(attrs, fn {attr_name, _, _} -> attr_name == name end) end
    loop = parse_loop(directive.(":for"), file)
    key = parse_directive(directive.(":key"), file)
    condition = parse_directive(directive.(":if"), file)

    if loop == nil != (key == nil) do
      raise ArgumentError, "#{file}:#{meta.line}: :for requires :key and :key requires :for"
    end

    if (directive.("$click") || directive.("$server")) && tag != "button" do
      raise ArgumentError, "#{file}:#{meta.line}: click events require a native button"
    end

    if (directive.("$input") || directive.("$change")) &&
         tag not in ~w(input select textarea form) do
      raise ArgumentError, "#{file}:#{meta.line}: input events require a native form control"
    end

    if directive.("$submit") && tag != "form" do
      raise ArgumentError, "#{file}:#{meta.line}: submit events require a form"
    end

    parsed_attrs =
      attrs
      |> Enum.reject(fn {name, _, _} -> name in ~w(:for :key :if) end)
      |> Enum.map(&convert_attr(&1, file))

    names = Enum.map(parsed_attrs, & &1.name)

    if "checked" in names and tag != "input" do
      raise ArgumentError, "#{file}:#{meta.line}: checked is only supported on input"
    end

    if "selected" in names and tag != "option" do
      raise ArgumentError, "#{file}:#{meta.line}: selected is only supported on option"
    end

    if tag == "textarea" and
         Enum.any?(children, fn child ->
           not match?({:text, _, _}, child) and not match?({:body_expr, _, _}, child)
         end) do
      raise ArgumentError, "#{file}:#{meta.line}: textarea supports only text and bindings"
    end

    if length(names) != length(Enum.uniq(names)) do
      raise ArgumentError, "#{file}:#{meta.line}: duplicate client attribute on <#{tag}>"
    end

    %{
      type: "element",
      tag: tag,
      attrs: parsed_attrs,
      children: Enum.map(children, &convert_node(&1, file)),
      void: tag in @void_tags,
      line: meta.line,
      for: loop,
      key: key,
      if: condition,
      node_id: if(condition || loop, do: "#{meta.line}:#{meta.column}", else: nil)
    }
  end

  defp parse_directive(nil, _file), do: nil

  defp parse_directive({_, {:expr, source, meta}, _}, file),
    do: Expression.parse(source, file, meta.line)

  defp parse_directive({name, _, meta}, file),
    do: raise(ArgumentError, "#{file}:#{meta.line}: #{name} requires an Elixir expression")

  defp parse_loop(nil, _file), do: nil

  defp parse_loop({":for", {:expr, source, meta}, _}, file) do
    case Code.string_to_quoted(source, file: file, line: meta.line) do
      {:ok, {:<-, _, [{var, _, context}, collection]}}
      when is_atom(var) and (is_atom(context) or is_nil(context)) ->
        %{
          var: Atom.to_string(var),
          source: Expression.parse(Macro.to_string(collection), file, meta.line)
        }

      _ ->
        raise ArgumentError, "#{file}:#{meta.line}: :for must be a single variable <- collection"
    end
  end

  defp parse_loop({_, _, meta}, file),
    do: raise(ArgumentError, "#{file}:#{meta.line}: :for requires an Elixir expression")

  defp convert_attr({name, {:string, value, _}, meta}, file) do
    if String.starts_with?(name, "phx-value-") do
      key = String.replace_prefix(name, "phx-value-", "")

      unless Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, key) and
               key not in ~w(__proto__ constructor prototype _live_lift_seq) do
        raise ArgumentError,
              "#{file}:#{meta.line}: unsafe phx-value parameter #{key}; use a safe field name"
      end
    end

    if Regex.match?(~r/^on[a-z]/i, name) or
         (name in ~w(href src action formaction) and
            Regex.match?(~r/^\s*javascript:/i, value)) do
      raise ArgumentError, "#{file}:#{meta.line}: unsafe client attribute: #{name}"
    end

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

  defp convert_attr({name, {:expr, source, meta}, _attr_meta}, file) do
    cond do
      name == ":params" ->
        %{
          name: "data-live-lift-params",
          value: Expression.parse(source, file, meta.line),
          type: "params"
        }

      name in ~w(checked selected) ->
        %{name: name, value: Expression.parse(source, file, meta.line), type: "boolean"}

      true ->
        raise ArgumentError,
              "#{file}:#{meta.line}: unsupported client expression attribute: #{name}={#{source}}"
    end
  end

  defp render_nodes(nodes, scope, stack),
    do: Enum.map_join(nodes, "", &render_node(&1, scope, stack))

  defp render_node(%{type: "text", value: value}, _scope, _stack), do: value

  defp render_node(%{type: "component", module: name, props: props}, scope, stack) do
    module = Module.concat(String.split(name, "."))

    if module in stack, do: raise(ArgumentError, "recursive LiveLift client component: #{name}")

    unless Code.ensure_loaded?(module) and
             function_exported?(module, :__live_lift_client_template__, 0) and
             function_exported?(module, :__live_lift_component__, 0) do
      raise ArgumentError, "unknown LiveLift client component: #{name}"
    end

    state =
      Map.new(props, fn %{name: key, expr: expr} ->
        {String.to_atom(key), Expression.eval(expr, scope)}
      end)

    LiveLift.State.validate!(state)

    render_nodes(module.__live_lift_client_template__(), %{"state" => state}, [module | stack])
  end

  defp render_node(%{type: "binding", expr: expr}, scope, _stack) do
    value = expr |> Expression.eval(scope) |> display_value() |> escape()
    "<!--live-lift:text-->#{value}<!--live-lift:end-->"
  end

  defp render_node(%{type: "element", for: %{var: var, source: source}} = node, scope, stack) do
    values = Expression.eval(source, scope)
    unless is_list(values), do: raise(ArgumentError, ":for expects a list")

    {markup, _keys} =
      Enum.map_reduce(values, MapSet.new(), fn value, keys ->
        item_scope = Map.put(scope, var, value)
        key = Expression.eval(node.key, item_scope)

        unless is_binary(key) or (is_integer(key) and abs(key) <= 9_007_199_254_740_991),
          do: raise(ArgumentError, ":key must be a string or safe integer")

        key_string = to_string(key)

        if MapSet.member?(keys, key_string),
          do: raise(ArgumentError, "duplicate client list key: #{key}")

        {render_element_node(%{node | for: nil}, item_scope, key, stack),
         MapSet.put(keys, key_string)}
      end)

    Enum.join(markup)
  end

  defp render_node(%{type: "element"} = node, scope, stack),
    do: render_element_node(node, scope, nil, stack)

  defp render_element_node(node, scope, key, stack) do
    if node.if && Expression.eval(node.if, scope) in [false, nil] do
      ""
    else
      render_element(node, scope, key, stack)
    end
  end

  defp render_element(node, scope, key, stack) do
    attrs = Enum.map_join(node.attrs, "", &render_attr(&1, scope))
    attrs = if hidden?(node.attrs, scope), do: attrs <> " hidden", else: attrs

    attrs =
      if key == nil, do: attrs, else: attrs <> " data-live-lift-key=\"#{escape(to_string(key))}\""

    attrs =
      if node.node_id == nil,
        do: attrs,
        else: attrs <> " data-live-lift-node-id=\"#{node.node_id}\""

    opening = "<#{node.tag}#{attrs}>"

    if node.void do
      opening
    else
      children =
        if node.tag == "textarea",
          do: Enum.map_join(node.children, "", &render_textarea_child(&1, scope)),
          else: render_nodes(node.children, scope, stack)

      opening <> children <> "</#{node.tag}>"
    end
  end

  defp render_textarea_child(%{type: "text", value: value}, _scope), do: value

  defp render_textarea_child(%{type: "binding", expr: expr}, scope),
    do: expr |> Expression.eval(scope) |> display_value() |> escape()

  defp render_attr(%{name: "data-live-lift-show", value: value}, _scope),
    do: " data-live-lift-show=\"#{value}\""

  defp render_attr(%{name: name, type: "static", value: value}, _scope),
    do: " #{name}=\"#{value}\""

  defp render_attr(%{name: name, type: "dynamic", value: expr}, scope) do
    value = expr |> Expression.eval(scope) |> display_value() |> escape()
    " #{name}=\"#{value}\" data-live-lift-bind-#{name}=\"#{path_label(expr)}\""
  end

  defp render_attr(%{name: name, type: "boolean", value: expr}, scope) do
    case Expression.eval(expr, scope) do
      true -> " #{name}"
      false -> ""
      nil -> ""
      _ -> raise ArgumentError, "#{name} requires a boolean or nil"
    end
  end

  defp render_attr(%{name: "data-live-lift-params", type: "params", value: expr}, scope) do
    payload = expr |> Expression.eval(scope) |> Jason.encode!() |> escape()
    " data-live-lift-params=\"#{payload}\""
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
