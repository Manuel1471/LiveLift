defmodule LiveLift.Component.Compiler do
  @moduledoc false

  alias LiveLift.Diagnostic

  def action!(event, params, socket, [do: result], file, line)
      when is_binary(event) do
    action = action_unchecked!(event, params, socket, [do: result], file, line)
    validate_action!(action, file, line)
    action
  end

  def action!(_event, _params, _socket, _body, file, line), do: invalid_handler!(file, line)

  def action_unchecked!(event, params, socket, [do: result], file, line)
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
          Diagnostic.error!("E057", file, source_line(params, line), Exception.message(error))
      end

    name = String.to_atom(event)
    args = if uses_params, do: [:state, :event], else: :state

    if used_variable?(params, body) do
      Diagnostic.error!(
        "E057",
        file,
        line,
        "@client supports params[\"name\"] and Map.get(params, \"name\"); move other parameter handling to the server"
      )
    end

    {name, args, body}
  end

  def action_unchecked!(_event, _params, _socket, _body, file, line),
    do: invalid_handler!(file, line)

  def validate_action!({name, args, body}, file, line) do
    try do
      LiveLift.Client.Compiler.compile_action(name, args, body)
    rescue
      error in ArgumentError ->
        reason = Exception.message(error)

        expression_error!(file, line, reason)
    end
  end

  defp expression_error!(file, line, "unsupported client changeset" <> _ = reason) do
    if String.contains?(reason, " (E052):") do
      raise ArgumentError,
            "#{file}:#{line}: unsupported @client handler: #{reason} " <>
              "Remove the @client marker to move it to a server handler."
    end

    Diagnostic.error!("E052", file, line, "unsupported @client handler: #{reason}")
  end

  defp expression_error!(file, line, reason),
    do: Diagnostic.error!("E056", file, line, "unsupported @client handler: #{reason}")

  defp invalid_handler!(file, line) do
    Diagnostic.error!(
      "E055",
      file,
      line,
      "@client handler must return {:noreply, assign/update(socket, ...)}; move other handlers to the server"
    )
  end

  defp update_to_state!(
         {:|>, _, [source, {operation, meta, args}]},
         socket_arg,
         file,
         line
       )
       when operation in [:assign, :update, :assign_new] and is_list(args) do
    update_to_state!({operation, meta, [source | args]}, socket_arg, file, line)
  end

  defp update_to_state!(
         {:assign_new, meta, [source, field, {:fn, _, [{:->, _, [[], fallback]}]}]},
         socket_arg,
         file,
         line
       )
       when is_atom(field) do
    state = state_source!(source, socket_arg, file, line)
    fallback = rewrite_original_socket_assigns(fallback, socket_arg)
    {:__live_lift_assign_new__, meta, [state, field, fallback]}
  end

  defp update_to_state!({:assign_new, _, _} = update, _socket_arg, file, line) do
    Diagnostic.error!(
      "E055",
      file,
      source_line(update, line),
      "@client assign_new/3 requires an atom key and a zero-argument function; keep other callbacks on the server"
    )
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

    expression = rewrite_original_socket_assigns(expression, {socket_name, [], nil})

    map_update(state, field, expression, meta)
  end

  defp update_to_state!(update, _socket, file, line) do
    Diagnostic.error!(
      "E055",
      file,
      source_line(update, line),
      "@client currently supports assign/3 and update/3; move other handlers to the server"
    )
  end

  defp state_source!({name, _, context}, {name, _, _}, _file, _line)
       when is_atom(context) or is_nil(context),
       do: {:state, [], nil}

  defp state_source!(source, socket_arg, file, line),
    do: update_to_state!(source, socket_arg, file, line)

  defp map_update(state, field, expression, meta) do
    {:%{}, meta, [{:|, meta, [state, [{field, expression}]]}]}
  end

  defp rewrite_original_socket_assigns(expression, {socket_name, _, _}) do
    Macro.prewalk(expression, fn
      {{:., _, [{{:., _, [{^socket_name, _, _}, :assigns]}, _, []}, key]}, _, []}
      when is_atom(key) ->
        # The lexical socket remains the original argument after an earlier pipe step.
        {{:., [], [{:state, [], nil}, key]}, [], []}

      other ->
        other
    end)
  end

  defp rewrite_params(body, {name, _, _}) when is_atom(name) and name != :%{} do
    Macro.prewalk(body, false, fn
      node, used ->
        case params_path(node, name) do
          {:ok, [_ | _] = path} -> {event_param(path), true}
          _ -> {node, used}
        end
    end)
  end

  defp rewrite_params(body, {:%{}, _, fields}) when is_list(fields) do
    bindings = pattern_bindings(fields, [])

    if length(bindings) != length(Enum.uniq_by(bindings, &elem(&1, 0))) do
      raise ArgumentError, "@client event pattern binds the same variable twice"
    end

    Macro.prewalk(body, false, fn
      {name, _, context} = node, used
      when is_atom(name) and (is_atom(context) or is_nil(context)) ->
        case List.keyfind(bindings, name, 0) do
          {_, path} -> {event_param(path), true}
          nil -> {node, used}
        end

      node, used ->
        {node, used}
    end)
  end

  defp rewrite_params(body, _params), do: {body, false}

  defp params_path({var, _, context}, name)
       when var == name and (is_atom(context) or is_nil(context)),
       do: {:ok, []}

  defp params_path({{:., _, [Access, :get]}, _, [source, key]}, name) when is_binary(key),
    do: append_param_path(source, name, key)

  defp params_path(
         {{:., _, [{:__aliases__, _, [:Map]}, :get]}, _, [source, key]},
         name
       )
       when is_binary(key),
       do: append_param_path(source, name, key)

  defp params_path(_node, _name), do: :error

  defp append_param_path(source, name, key) do
    case params_path(source, name) do
      {:ok, path} -> {:ok, path ++ [key]}
      _ -> :error
    end
  end

  defp pattern_bindings(fields, prefix) do
    Enum.flat_map(fields, fn
      {key, {name, _, context}}
      when is_binary(key) and is_atom(name) and (is_atom(context) or is_nil(context)) ->
        [{name, prefix ++ [key]}]

      {key, {:%{}, _, nested}} when is_binary(key) and is_list(nested) and nested != [] ->
        pattern_bindings(nested, prefix ++ [key])

      _ ->
        raise ArgumentError,
              "@client supports string-key event map patterns up to four segments; move other patterns to a server handler"
    end)
  end

  defp event_param(path) when is_list(path) do
    unless length(path) in 1..4 and
             Enum.all?(path, fn key ->
               Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, key) and
                 key not in ~w(__proto__ constructor prototype _live_lift_seq)
             end) do
      raise ArgumentError, "unsupported @client event parameter path: #{Enum.join(path, ".")}"
    end

    root = {{:., [], [{:event, [], nil}, :params]}, [], []}

    Enum.reduce(path, root, fn key, source ->
      {{:., [], [source, String.to_atom(key)]}, [], []}
    end)
  end

  defp source_line({_, meta, _}, fallback) when is_list(meta),
    do: Keyword.get(meta, :line, fallback)

  defp source_line(_, fallback), do: fallback

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
