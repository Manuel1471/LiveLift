defmodule LiveLift.Component.Helpers do
  @moduledoc false

  alias LiveLift.Diagnostic

  @max_expanded_nodes 50_000
  @max_helper_calls 1_000

  def expand!(body, definitions, file, line) do
    registry =
      Enum.group_by(definitions, fn {name, args, _guards, _body, _file, _line} ->
        {name, length(args)}
      end)

    body = normalize_pipes(body)
    {expanded, _budget} = expand(body, registry, [], file, line, {0, 0})
    expanded
  end

  defp expand(ast, registry, stack, file, line, budget) do
    Macro.postwalk(ast, budget, fn
      {name, metadata, args} = call, budget when is_atom(name) and is_list(args) ->
        budget = charge_node!(budget, file, line)
        key = {name, length(args)}

        case Map.fetch(registry, key) do
          {:ok, clauses} ->
            expand_call!(key, metadata, args, clauses, registry, stack, file, line, budget)

          :error ->
            {call, budget}
        end

      other, budget ->
        {other, charge_node!(budget, file, line)}
    end)
  end

  defp expand_call!(
         {name, arity} = key,
         metadata,
         args,
         clauses,
         registry,
         stack,
         file,
         line,
         {nodes, calls}
       ) do
    if key in stack do
      Diagnostic.error!(
        "E058",
        file,
        line,
        "recursive client helper #{name}/#{arity} is not supported; move this handler to the server"
      )
    end

    if calls >= @max_helper_calls do
      Diagnostic.error!(
        "E058",
        file,
        line,
        "client helper expansion limit exceeded; split the handler or keep it on the server"
      )
    end

    {branches, budget} =
      Enum.map_reduce(clauses, {nodes, calls + 1}, fn
        {_name, patterns, guards, body, helper_file, helper_line}, budget ->
          if guards != [] do
            Diagnostic.error!(
              "E058",
              helper_file,
              helper_line,
              "client helper #{name}/#{arity} has a guard; use an unguarded clause or move this handler to the server"
            )
          end

          expression =
            case body do
              [do: expression] ->
                expression

              _ ->
                Diagnostic.error!(
                  "E058",
                  helper_file,
                  helper_line,
                  "client helper #{name}/#{arity} needs one expression body; move this handler to the server"
                )
            end

          {expression, budget} = expand(expression, registry, [key | stack], file, line, budget)
          patterns = Enum.map(patterns, &unwrap_pattern/1)
          {{:->, metadata, [[patterns], expression]}, budget}
      end)

    failure =
      {:->, metadata,
       [
         [[{:_, metadata, nil}]],
         {:__live_lift_helper_failure__, metadata, ["#{name}/#{arity}"]}
       ]}

    {{:case, metadata, [args, [do: branches ++ [failure]]]}, budget}
  end

  defp charge_node!({nodes, calls}, file, line) do
    if nodes >= @max_expanded_nodes do
      Diagnostic.error!(
        "E058",
        file,
        line,
        "client helper expansion limit exceeded; split the handler or keep it on the server"
      )
    end

    {nodes + 1, calls}
  end

  defp unwrap_pattern(pattern) do
    Macro.postwalk(pattern, fn
      {{:., _, [Phoenix.Component.Declarative, :__pattern__!]}, _, [:defp, inner]} -> inner
      other -> other
    end)
  end

  defp normalize_pipes(ast) do
    Macro.postwalk(ast, fn
      {:|>, _, [source, {callee, metadata, arguments}]} when is_list(arguments) ->
        {callee, metadata, [source | arguments]}

      other ->
        other
    end)
  end
end
