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

    if used_variable?(params, update) do
      raise ArgumentError,
            "#{file}:#{line}: @client handler reads event params; move it to a server handler for now"
    end

    body = update_to_state!(update, socket, file, line)
    name = String.to_atom(event)

    try do
      LiveLift.Client.Compiler.compile_action(name, :state, body)
    rescue
      error in ArgumentError ->
        raise ArgumentError,
              "#{file}:#{line}: unsupported @client handler: #{Exception.message(error)}; move it to a server handler"
    end

    {name, :state, body}
  end

  def action!(_event, _params, _socket, _body, file, line), do: invalid_handler!(file, line)

  defp invalid_handler!(file, line) do
    raise ArgumentError,
          "#{file}:#{line}: @client handler must return {:noreply, assign/update(socket, ...)}; move other handlers to the server"
  end

  defp update_to_state!(
         {:update, meta, [{socket_name, _, _}, field, {:&, _, [expression]}]},
         {socket_name, _, _},
         _file,
         _line
       )
       when is_atom(field) do
    replacement = {{:., [], [{:state, [], nil}, field]}, [], []}

    expression =
      Macro.prewalk(expression, fn
        {:&, _, [1]} -> replacement
        other -> other
      end)

    map_update(field, expression, meta)
  end

  defp update_to_state!(
         {:assign, meta, [{socket_name, _, _}, field, expression]},
         {socket_name, _, _},
         _file,
         _line
       )
       when is_atom(field) do
    expression =
      Macro.prewalk(expression, fn
        {{:., _, [{{:., _, [{^socket_name, _, _}, :assigns]}, _, []}, key]}, _, []}
        when is_atom(key) ->
          {{:., [], [{:state, [], nil}, key]}, [], []}

        other ->
          other
      end)

    map_update(field, expression, meta)
  end

  defp update_to_state!(_update, _socket, file, line) do
    raise ArgumentError,
          "#{file}:#{line}: @client currently supports assign/3 and update/3; move other handlers to the server"
  end

  defp map_update(field, expression, meta) do
    {:%{}, meta, [{:|, meta, [{:state, meta, nil}, [{field, expression}]]}]}
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
