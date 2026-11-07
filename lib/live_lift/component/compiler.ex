defmodule LiveLift.Component.Compiler do
  @moduledoc false

  def action!(event, params, socket, [do: result], file, line)
      when is_binary(event) do
    update =
      case result do
        {:{}, _, [:noreply, update]} -> update
        {:noreply, update} -> update
        _ -> invalid_handler!(file, line)
      end

    body = update_to_state!(update, socket, file, line)

    {body, uses_params} =
      try do
        rewrite_params(body, params)
      rescue
        error in ArgumentError ->
          raise ArgumentError, "#{file}:#{line}: #{Exception.message(error)}"
      end

    name = String.to_atom(event)
    args = if uses_params, do: [:state, :event], else: :state

    if used_variable?(params, body) do
      raise ArgumentError,
            "#{file}:#{line}: @client supports params[\"name\"] and Map.get(params, \"name\"); move other parameter handling to the server"
    end

    try do
      LiveLift.Client.Compiler.compile_action(name, args, body)
    rescue
      error in ArgumentError ->
        raise ArgumentError,
              "#{file}:#{line}: unsupported @client handler: #{Exception.message(error)}; move it to a server handler"
    end

    {name, args, body}
  end

  def action!(_event, _params, _socket, _body, file, line), do: invalid_handler!(file, line)

  defp invalid_handler!(file, line) do
    raise ArgumentError,
          "#{file}:#{line}: @client handler must return {:noreply, assign/update(socket, ...)}; move other handlers to the server"
  end

  defp update_to_state!(
         {:|>, _, [source, {operation, meta, args}]},
         socket_arg,
         file,
         line
       )
       when operation in [:assign, :update] and is_list(args) do
    update_to_state!({operation, meta, [source | args]}, socket_arg, file, line)
  end

  defp update_to_state!(
         {:update, meta, [source, field, {:&, _, [expression]}]},
         socket_arg,
         file,
         line
       )
       when is_atom(field) do
    state = state_source!(source, socket_arg, file, line)
    replacement = {{:., [], [state, field]}, [], []}

    expression =
      Macro.prewalk(expression, fn
        {:&, _, [1]} -> replacement
        other -> other
      end)

    map_update(state, field, expression, meta)
  end

  defp update_to_state!(
         {:assign, meta, [source, field, expression]},
         {socket_name, _, _} = socket_arg,
         file,
         line
       )
       when is_atom(field) do
    state = state_source!(source, socket_arg, file, line)

    expression =
      Macro.prewalk(expression, fn
        {{:., _, [{{:., _, [{^socket_name, _, _}, :assigns]}, _, []}, key]}, _, []}
        when is_atom(key) ->
          {{:., [], [{:state, [], nil}, key]}, [], []}

        other ->
          other
      end)

    map_update(state, field, expression, meta)
  end

  defp update_to_state!(_update, _socket, file, line) do
    raise ArgumentError,
          "#{file}:#{line}: @client currently supports assign/3 and update/3; move other handlers to the server"
  end

  defp state_source!({name, _, context}, {name, _, _}, _file, _line)
       when is_atom(context) or is_nil(context),
       do: {:state, [], nil}

  defp state_source!(source, socket_arg, file, line),
    do: update_to_state!(source, socket_arg, file, line)

  defp map_update(state, field, expression, meta) do
    {:%{}, meta, [{:|, meta, [state, [{field, expression}]]}]}
  end

  defp rewrite_params(body, {name, _, _}) when is_atom(name) and name != :%{} do
    Macro.prewalk(body, false, fn
      {{:., _, [Access, :get]}, _, [{^name, _, _}, key]}, _used when is_binary(key) ->
        {event_param(key), true}

      {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [{^name, _, _}, key]}, _used
      when is_binary(key) ->
        {event_param(key), true}

      node, used ->
        {node, used}
    end)
  end

  defp rewrite_params(body, {:%{}, _, fields}) when is_list(fields) do
    bindings =
      Enum.map(fields, fn
        {key, {name, _, context}}
        when is_binary(key) and is_atom(name) and (is_atom(context) or is_nil(context)) ->
          {name, key}

        _ ->
          raise ArgumentError,
                "@client supports flat string-key event patterns; move nested patterns to a server handler"
      end)

    if length(bindings) != length(Enum.uniq_by(bindings, &elem(&1, 0))) do
      raise ArgumentError, "@client event pattern binds the same variable twice"
    end

    Macro.prewalk(body, false, fn
      {name, _, context} = node, used
      when is_atom(name) and (is_atom(context) or is_nil(context)) ->
        case List.keyfind(bindings, name, 0) do
          {_, key} -> {event_param(key), true}
          nil -> {node, used}
        end

      node, used ->
        {node, used}
    end)
  end

  defp rewrite_params(body, _params), do: {body, false}

  defp event_param(key) do
    unless Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, key) and
             key not in ~w(__proto__ constructor prototype _live_lift_seq) do
      raise ArgumentError, "unsupported @client event parameter: #{key}"
    end

    {{:., [], [{{:., [], [{:event, [], nil}, :params]}, [], []}, String.to_atom(key)]}, [], []}
  end

  defp used_variable?({name, _, context}, ast)
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {^name, _, variable_context} = node, _found
        when is_atom(variable_context) or is_nil(variable_context) ->
          {node, true}

        node, found ->
          {node, found}
      end)

    found
  end

  defp used_variable?(_, _), do: false
end
