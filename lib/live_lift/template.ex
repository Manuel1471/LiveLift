defmodule LiveLift.Template do
  @moduledoc "Parses client templates into a validated tree shared by both runtimes."

  alias LiveLift.Template.Expression
  alias LiveLift.Template.Parser

  @dynamic_attributes ~w(class title aria-label value)
  @native_dynamic_attributes ~w(class title aria-label value id)
  @events ~w($click $server $input $change $submit)
  @void_tags ~w(area base br col embed hr img input link meta param source track wbr)
  @forbidden_tags ~w(script iframe object embed base link meta style foreignobject animate animatemotion animatetransform set)

  @spec compile(String.t(), String.t()) :: list(map())
  def compile(source, file \\ "nofile") when is_binary(source) do
    source |> Parser.parse!(file) |> compile_parsed(file, :legacy)
  end

  @doc false
  def compile_liveview(source, file, client_events, local_components \\ %{})
      when is_binary(source) do
    source
    |> Parser.parse!(file)
    |> compile_parsed(file, {:liveview, client_events, local_components})
  end

  @doc false
  def compile_parsed(nodes, file, :legacy) do
    tree = Enum.map(nodes, &convert_node(&1, file))

    if Enum.any?(tree, &local_component_node?/1) do
      raise ArgumentError,
            "#{file}: local function components require a native LiveComponent with use LiveLift"
    end

    if Enum.any?(tree, &default_slot_node?/1) do
      raise ArgumentError,
            "#{file}: render_slot(@inner_block) requires a native local function component"
    end

    tree
  end

  def compile_parsed(nodes, file, {:liveview, events}) do
    compile_parsed(nodes, file, {:liveview, events, %{}})
  end

  def compile_parsed(nodes, file, {:liveview, events, local_components}) do
    tree =
      nodes
      |> Enum.map(&adapt_liveview_node(&1, file, events))
      |> Enum.map(&convert_node(&1, file))
      |> expand_local_components(local_components, file, events, [])

    if Enum.any?(tree, &default_slot_node?/1) do
      raise ArgumentError,
            "#{file}: render_slot(@inner_block) requires a local function component call; move this expression to the server"
    end

    tree
  end

  defp local_component_node?(%{type: "local_component"}), do: true

  defp local_component_node?(%{type: "element", children: children}),
    do: Enum.any?(children, &local_component_node?/1)

  defp local_component_node?(_), do: false

  defp default_slot_node?(%{type: "default_slot"}), do: true

  defp default_slot_node?(%{type: "element", children: children}),
    do: Enum.any?(children, &default_slot_node?/1)

  defp default_slot_node?(_), do: false

  defp adapt_liveview_node({:block, type, tag, attrs, children, meta, close}, file, events) do
    validate_native_debounce!(tag, attrs, file, meta.line)

    if type == :remote_component do
      raise ArgumentError,
            "#{file}:#{meta.line}: remote function component #{tag} is not supported in @client yet; use a local function component or keep this subtree on the server"
    end

    if tag == "form" and marked_change_descendant?(children, events) do
      raise ArgumentError,
            "#{file}:#{meta.line}: @client input phx-change inside a form is not supported yet; put phx-change on the form or keep this event on the server"
    end

    if tag == "form" and marked_event?(attrs, events) do
      validate_form!(children, file, meta.line)
    end

    {:block, type, tag, attrs |> native_loop_key(file) |> adapt_liveview_attrs(file, events),
     Enum.map(children, &adapt_liveview_node(&1, file, events)), meta, close}
  end

  defp adapt_liveview_node({:self_close, type, tag, attrs, meta}, file, events) do
    validate_native_debounce!(tag, attrs, file, meta.line)

    if type == :remote_component do
      raise ArgumentError,
            "#{file}:#{meta.line}: remote function component #{tag} is not supported in @client yet; use a local function component or keep this subtree on the server"
    end

    validate_change_control!(tag, attrs, file, meta.line, events)

    {:self_close, type, tag, attrs |> native_loop_key(file) |> adapt_liveview_attrs(file, events),
     meta}
  end

  defp adapt_liveview_node(node, _file, _events), do: node

  defp validate_native_debounce!(tag, attrs, file, line) do
    Enum.each(attrs, fn
      {"phx-debounce", {:string, value, _}, _} ->
        unless tag in ~w(input textarea) and
                 (value in ["", "blur"] or
                    (byte_size(value) <= 10 and Regex.match?(~r/^(0|[1-9][0-9]*)$/, value) and
                       String.to_integer(value) <= 2_147_483_647)) do
          raise ArgumentError,
                "#{file}:#{line}: @client phx-debounce supports an input or textarea with a nonnegative millisecond value or blur; keep this event on the server"
        end

      {"phx-debounce", _, _} ->
        raise ArgumentError,
              "#{file}:#{line}: @client phx-debounce requires a static millisecond value or blur; keep this event on the server"

      _ ->
        :ok
    end)
  end

  defp marked_change_descendant?(nodes, events) do
    Enum.any?(nodes, fn
      {:block, _, _, attrs, children, _, _} ->
        marked_change_attr?(attrs, events) or marked_change_descendant?(children, events)

      {:self_close, _, _, attrs, _} ->
        marked_change_attr?(attrs, events)

      _ ->
        false
    end)
  end

  defp marked_change_attr?(attrs, events) do
    Enum.any?(attrs, fn
      {"phx-change", {:string, event, _}, _} -> event in events
      _ -> false
    end)
  end

  defp native_loop_key(attrs, file) do
    loop = Enum.find(attrs, fn {name, _, _} -> name == ":for" end)
    key = Enum.find(attrs, fn {name, _, _} -> name == ":key" end)

    if loop && !key do
      %{var: var} = parse_loop(loop, file)
      id = Enum.find(attrs, fn {name, _, _} -> name == "id" end)

      case id do
        {"id", {:expr, source, meta} = value, attr_meta} ->
          case Expression.parse(source, file, meta.line) do
            %{type: "path", root: ^var, fields: [_ | _]} ->
              attrs ++ [{":key", value, attr_meta}]

            _ ->
              raise ArgumentError,
                    "#{file}:#{meta.line}: @client :for requires id={#{var}.id} from the repeated item; use a stable item id or keep this list on the server"
          end

        _ ->
          {_, _, meta} = loop

          raise ArgumentError,
                "#{file}:#{meta.line}: @client :for requires id={#{var}.id} on the repeated element; use a stable item id or keep this list on the server"
      end
    else
      attrs
    end
  end

  defp marked_event?(attrs, events) do
    Enum.any?(attrs, fn
      {name, {:string, event, _}, _} when name in ~w(phx-change phx-submit) ->
        event in events

      _ ->
        false
    end)
  end

  defp validate_change_control!(tag, attrs, file, line, events)
       when tag in ~w(input select textarea) do
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

      Enum.each(attrs, fn
        {"name", {:string, name, _}, _} ->
          unless Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name) and
                   name not in ~w(__proto__ constructor prototype _live_lift_seq) do
            raise ArgumentError,
                  "#{file}:#{line}: @client direct phx-change requires a flat safe input name; put phx-change on the form for nested map names"
          end

        {"name", _, _} ->
          raise ArgumentError,
                "#{file}:#{line}: @client direct phx-change requires a static input name; move this event to the server"

        _ ->
          :ok
      end)
    end
  end

  defp validate_change_control!(_tag, _attrs, _file, _line, _events), do: :ok

  defp validate_form!(children, file, line) do
    names = form_names(children, file)

    if unsupported_form_control?(children) do
      raise ArgumentError,
            "#{file}:#{line}: @client form has a checkbox, radio, file or multiple-select control; keep this event on the server"
    end

    paths =
      for name <- names do
        unless Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*(\[[a-zA-Z_][a-zA-Z0-9_]*\]){0,3}$/, name) do
          raise ArgumentError,
                "#{file}:#{line}: @client form requires safe map input names with at most four segments; keep arrays or deeper forms on the server"
        end

        path = Regex.scan(~r/[a-zA-Z_][a-zA-Z0-9_]*/, name) |> List.flatten()

        if Enum.any?(path, &(&1 in ~w(__proto__ constructor prototype _live_lift_seq))) do
          raise ArgumentError,
                "#{file}:#{line}: @client form has an unsafe input name; use safe map keys"
        end

        path
      end

    if length(paths) != length(Enum.uniq(paths)) do
      raise ArgumentError,
            "#{file}:#{line}: @client form has duplicate input names; move this event to a server handler"
    end

    if Enum.any?(paths, fn path ->
         Enum.any?(paths, fn other ->
           path != other and Enum.take(other, length(path)) == path
         end)
       end) do
      raise ArgumentError,
            "#{file}:#{line}: @client form has conflicting map input names; keep this event on the server"
    end
  end

  defp form_names(nodes, file) do
    Enum.flat_map(nodes, fn
      {:block, :tag, _tag, attrs, children, meta, _} ->
        form_name(attrs, file, meta.line) ++ form_names(children, file)

      {:self_close, :tag, _tag, attrs, meta} ->
        form_name(attrs, file, meta.line)

      _ ->
        []
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

  defp form_name(attrs, file, line) do
    Enum.flat_map(attrs, fn
      {"name", {:string, value, _}, _} ->
        [value]

      {"name", _, _} ->
        raise ArgumentError,
              "#{file}:#{line}: @client form requires static input names; move this event to the server"

      _ ->
        []
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

  defp convert_node({:body_expr, source, meta}, file) do
    case Code.string_to_quoted(source, file: file, line: meta.line) do
      {:ok, {:render_slot, _, [{:@, _, [{:inner_block, _, _}]}]}} ->
        %{type: "default_slot", line: meta.line}

      _ ->
        %{type: "binding", expr: Expression.parse(source, file, meta.line)}
    end
  end

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

  defp convert_element(:local_component, tag, attrs, children, meta, file) do
    props =
      Enum.map(attrs, fn
        {name, {:expr, source, expression_meta}, _} when is_binary(name) ->
          validate_local_prop_name!(name, file, meta.line)
          %{name: name, expr: Expression.parse(source, file, expression_meta.line)}

        {name, {:string, value, _}, _} when is_binary(name) ->
          validate_local_prop_name!(name, file, meta.line)

          if Regex.match?(~r/&(?:#[0-9]+|#[xX][0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]+);/, value) do
            raise ArgumentError,
                  "#{file}:#{meta.line}: encoded function component prop #{name} is not supported; pass an Elixir string expression instead"
          end

          %{name: name, expr: %{type: "literal", value: value}}

        {name, _, _} ->
          raise ArgumentError,
                "#{file}:#{meta.line}: client function component prop #{name} requires a value"
      end)

    if length(props) != length(Enum.uniq_by(props, & &1.name)) do
      raise ArgumentError, "#{file}:#{meta.line}: duplicate client function component prop"
    end

    %{
      type: "local_component",
      name: String.trim_leading(tag, "."),
      props: props,
      children: Enum.map(children, &convert_node(&1, file)),
      line: meta.line,
      column: meta.column
    }
  end

  defp convert_element(:slot, tag, _attrs, _children, meta, file) do
    raise ArgumentError,
          "#{file}:#{meta.line}: slot #{tag} is not supported in client function components yet; move this component to the server"
  end

  defp convert_element(type, tag, attrs, children, meta, file) do
    unless type == :tag do
      raise ArgumentError, "#{file}:#{meta.line}: client components are not supported yet: #{tag}"
    end

    if String.downcase(tag) in @forbidden_tags do
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

  defp validate_local_prop_name!(name, file, line) do
    unless Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, name) and
             name not in ~w(__proto__ constructor prototype) do
      raise ArgumentError,
            "#{file}:#{line}: client function component supports named props only; move directives or slots to the server"
    end
  end

  defp expand_local_components(nodes, components, file, events, stack) do
    Enum.flat_map(nodes, fn
      %{
        type: "local_component",
        name: name,
        props: props,
        children: children,
        line: line,
        column: column
      } ->
        if name in stack do
          raise ArgumentError, "#{file}:#{line}: recursive client function component .#{name}"
        end

        component =
          Map.get(components, name) ||
            raise(
              ArgumentError,
              "#{file}:#{line}: unknown client function component .#{name}; define a local function returning literal ~H or move it to the server"
            )

        props = Map.new(props, fn %{name: key, expr: expr} -> {key, expr} end)
        children = expand_local_components(children, components, file, events, stack)

        body =
          component.source
          |> Parser.parse!(component.file)
          |> Enum.map(&adapt_liveview_node(&1, component.file, events))
          |> Enum.map(&convert_node(&1, component.file))
          |> expand_local_components(components, component.file, events, [name | stack])

        slot_count = Enum.sum(Enum.map(body, &count_default_slots/1))

        if slot_count > 1 do
          raise ArgumentError,
                "#{component.file}:#{component.line}: client function component .#{name} may render its default slot once; move repeated slots to the server"
        end

        if children != [] and slot_count == 0 do
          raise ArgumentError,
                "#{file}:#{line}: client function component .#{name} does not render its default slot; remove children or add render_slot(@inner_block)"
        end

        body
        |> Enum.map(&wrap_default_slot(&1, children))
        |> Enum.map(&substitute_component_props(&1, props, file, line, "#{line}:#{column}"))
        |> flatten_slot_scopes()

      %{type: "element", children: children} = node ->
        [%{node | children: expand_local_components(children, components, file, events, stack)}]

      node ->
        [node]
    end)
  end

  defp count_default_slots(%{type: "default_slot"}), do: 1

  defp count_default_slots(%{type: "element", children: children}),
    do: Enum.sum(Enum.map(children, &count_default_slots/1))

  defp count_default_slots(_), do: 0

  defp wrap_default_slot(%{type: "default_slot"}, children),
    do: %{type: "slot_scope", children: children}

  defp wrap_default_slot(%{type: "element", children: children} = node, slot),
    do: %{node | children: Enum.map(children, &wrap_default_slot(&1, slot))}

  defp wrap_default_slot(node, _children), do: node

  defp flatten_slot_scopes(nodes) do
    Enum.flat_map(nodes, fn
      %{type: "slot_scope", children: children} ->
        children

      %{type: "element", children: children} = node ->
        [%{node | children: flatten_slot_scopes(children)}]

      node ->
        [node]
    end)
  end

  defp substitute_component_props(%{type: "slot_scope"} = node, _props, _file, _line, _prefix),
    do: node

  defp substitute_component_props(
         %{type: "binding", expr: expr} = node,
         props,
         file,
         line,
         _prefix
       ),
       do: %{node | expr: substitute_prop_expr(expr, props, file, line)}

  defp substitute_component_props(%{type: "element"} = node, props, file, line, prefix) do
    attrs =
      Enum.map(node.attrs, fn
        %{type: type, value: value} = attr
        when type in ~w(dynamic native_dynamic boolean params) ->
          %{attr | value: substitute_prop_expr(value, props, file, line)}

        attr ->
          attr
      end)

    node
    |> Map.put(:attrs, attrs)
    |> Map.update!(:children, fn children ->
      Enum.map(children, &substitute_component_props(&1, props, file, line, prefix))
    end)
    |> Map.update!(:for, fn
      nil -> nil
      loop -> %{loop | source: substitute_prop_expr(loop.source, props, file, line)}
    end)
    |> Map.update!(:key, fn
      nil -> nil
      key -> substitute_prop_expr(key, props, file, line)
    end)
    |> Map.update!(:if, fn
      nil -> nil
      condition -> substitute_prop_expr(condition, props, file, line)
    end)
    |> Map.update!(:node_id, fn
      nil -> nil
      id -> "#{prefix}/#{id}"
    end)
  end

  defp substitute_component_props(node, _props, _file, _line, _prefix), do: node

  defp substitute_prop_expr(
         %{type: "path", root: "state", fields: [name | rest]},
         props,
         file,
         line
       ) do
    case Map.fetch(props, name) do
      {:ok, %{type: "path"} = source} ->
        %{source | fields: source.fields ++ rest}

      {:ok, source} when rest == [] ->
        source

      {:ok, _source} ->
        raise ArgumentError,
              "#{file}:#{line}: function component prop #{name} cannot be read as a map"

      :error ->
        raise ArgumentError, "#{file}:#{line}: missing function component prop #{name}"
    end
  end

  defp substitute_prop_expr(%{type: "map", entries: entries} = expr, props, file, line),
    do: %{
      expr
      | entries:
          Enum.map(entries, fn entry ->
            %{entry | expr: substitute_prop_expr(entry.expr, props, file, line)}
          end)
    }

  defp substitute_prop_expr(%{type: "list", items: items} = expr, props, file, line),
    do: %{expr | items: Enum.map(items, &substitute_prop_expr(&1, props, file, line))}

  defp substitute_prop_expr(%{type: "and", left: left, right: right} = expr, props, file, line),
    do: %{
      expr
      | left: substitute_prop_expr(left, props, file, line),
        right: substitute_prop_expr(right, props, file, line)
    }

  defp substitute_prop_expr(expr, _props, _file, _line), do: expr

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
    validate_phx_value_name!(name, file, meta.line)

    if Regex.match?(~r/^on[a-z]/i, name) do
      raise ArgumentError, "#{file}:#{meta.line}: unsafe client attribute: #{name}"
    end

    url_name = String.downcase(name)

    if url_name in ~w(href xlink:href src action formaction),
      do: validate_static_url!(url_name, value, file, meta.line)

    if url_name == "xml:base",
      do: raise(ArgumentError, "#{file}:#{meta.line}: unsafe client attribute: xml:base")

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
    validate_phx_value_name!(name, file, meta.line)

    cond do
      name == ":params" ->
        %{
          name: "data-live-lift-params",
          value: Expression.parse(source, file, meta.line),
          type: "params"
        }

      name in ~w(checked selected) ->
        %{name: name, value: Expression.parse(source, file, meta.line), type: "boolean"}

      name in @native_dynamic_attributes or String.starts_with?(name, "phx-value-") ->
        %{name: name, value: Expression.parse(source, file, meta.line), type: "native_dynamic"}

      true ->
        raise ArgumentError,
              "#{file}:#{meta.line}: unsupported client expression attribute: #{name}={#{source}}"
    end
  end

  defp validate_phx_value_name!(name, file, line) do
    if String.starts_with?(name, "phx-value-") do
      key = String.replace_prefix(name, "phx-value-", "")

      unless Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, key) and
               key not in ~w(__proto__ constructor prototype _live_lift_seq) do
        raise ArgumentError,
              "#{file}:#{line}: unsafe phx-value parameter #{key}; use a safe field name"
      end
    end
  end

  defp validate_static_url!(name, value, file, line) do
    leading = String.trim_leading(value) |> String.split(~r{[/?#]}, parts: 2) |> hd()
    allowed = if name in ~w(href xlink:href), do: ~w(http https mailto tel), else: ~w(http https)

    scheme =
      case String.split(leading, ":", parts: 2) do
        [prefix, _rest] -> String.downcase(prefix)
        [_relative] -> nil
      end

    if String.contains?(leading, "&") or
         Regex.match?(~r/[\x00-\x1F\x7F]/, leading) or
         (scheme && scheme not in allowed) do
      raise ArgumentError,
            "#{file}:#{line}: unsafe client attribute: #{name}; use a relative or allowed URL scheme without HTML entities in its prefix"
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

  defp render_attr(%{name: name, type: "native_dynamic", value: expr}, scope) do
    value = Expression.eval(expr, scope)

    if name != "class" and is_list(value) do
      raise ArgumentError, "#{name} requires a scalar value"
    end

    value =
      if name == "class" and is_list(value), do: native_class_value(expr, value), else: value

    Phoenix.HTML.attributes_escape([{String.to_atom(name), value}])
    |> Phoenix.HTML.safe_to_string()
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

  defp native_class_value(%{type: "list", items: items}, values) do
    count =
      Enum.take_while(items, &match?(%{type: "literal", value: value} when is_binary(value), &1))
      |> length()

    if count > 0 and count < length(items) do
      class_list_value(Enum.take(values, count)) <>
        " " <>
        class_list_value(Enum.drop(values, count))
    else
      class_list_value(values)
    end
  end

  defp native_class_value(_expr, values), do: class_list_value(values)

  defp class_list_value(values) do
    values |> class_tokens() |> Enum.join(" ")
  end

  defp class_tokens(values) do
    Enum.flat_map(values, fn
      nil -> []
      false -> []
      inner when is_list(inner) -> class_tokens(inner)
      other -> [to_string(other)]
    end)
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
