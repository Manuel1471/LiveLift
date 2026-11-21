defmodule Mix.Tasks.LiveLift.Audit do
  @moduledoc """
  Reports which LiveView and LiveComponent handlers fit LiveLift's current client subset.

      mix live_lift.audit
      mix live_lift.audit --path lib/my_app_web

  This is a source audit. It does not modify files or mark handlers for the
  client. A compatible result still needs normal tests and a browser check.
  """

  use Mix.Task

  alias LiveLift.Component.{Compiler, Helpers, ProcessTimer, Timer}

  @shortdoc "Reports client-compatible LiveView and LiveComponent handlers"

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: [path: :string])

    if invalid != [] or rest != [],
      do: Mix.raise("usage: mix live_lift.audit [--path lib/my_app_web]")

    path = opts[:path] || "lib"
    files = if File.regular?(path), do: [path], else: Path.wildcard(Path.join(path, "**/*.ex"))

    if files == [], do: Mix.raise("no Elixir source files found at #{path}")

    results = Enum.flat_map(files, &audit_file/1)

    for {file, line, module, event, result} <- results do
      Mix.shell().info("#{file}:#{line}: #{module}.handle_event(#{inspect(event)}): #{result}")
    end

    compatible = Enum.count(results, fn {_, _, _, _, result} -> result == "compatible" end)

    Mix.shell().info(
      "#{compatible}/#{length(results)} handlers compatible with the current subset"
    )
  end

  defp audit_file(file) do
    source = File.read!(file)

    case Code.string_to_quoted(source, file: file) do
      {:ok, ast} ->
        {_ast, modules} =
          Macro.prewalk(ast, [], fn
            {:defmodule, _, [name, [do: body]]} = node, acc ->
              {node, [{Macro.to_string(name), body} | acc]}

            node, acc ->
              {node, acc}
          end)

        modules
        |> Enum.reverse()
        |> Enum.flat_map(fn {name, body} -> audit_module(file, name, body) end)

      {:error, {location, message, _token}} ->
        line = if is_list(location), do: Keyword.get(location, :line), else: location
        [{file, line, "source", "parse", "blocked: #{message}"}]
    end
  end

  defp audit_module(file, name, body) do
    expressions = if match?({:__block__, _, _}, body), do: elem(body, 2), else: [body]

    case Enum.find_value(expressions, &view_kind/1) do
      nil ->
        []

      kind ->
        template = Enum.find_value(expressions, &render_source/1)
        definitions = source_definitions(expressions, file)

        handlers =
          for {:handle_event, [event, params, socket], guards, body, env} <- definitions,
              do: {event, params, socket, guards, body, env}

        callbacks =
          for {:handle_info, [message, socket], guards, body, env} <- definitions,
              do: {message, socket, guards, body, file, env.line}

        context = %{
          helpers: Enum.flat_map(expressions, &helper_definition(&1, file)),
          callbacks: callbacks,
          live_view?: kind == :view,
          custom_update?: Enum.any?(definitions, &custom_update?/1),
          kernel_self?: Enum.all?(expressions, &preserves_kernel_self?/1)
        }

        duplicates = Enum.frequencies_by(handlers, &elem(&1, 0))

        for {event, params, socket, guards, body, env} <- handlers do
          status =
            cond do
              not is_binary(event) or guards != [] ->
                "blocked: use a literal event name without a guard or keep this handler on the server"

              Map.get(duplicates, event) > 1 ->
                "blocked: multiple clauses for this event; keep it on the server"

              template == nil ->
                "blocked: render/1 must return a literal ~H template"

              true ->
                check_handler(env, event, params, socket, body, template, context)
            end

          {file, env.line, name, event, status}
        end
    end
  end

  defp view_kind({:use, _, [{:__aliases__, _, [:Phoenix, :LiveComponent]} | _]}), do: :component
  defp view_kind({:use, _, [{:__aliases__, _, [:Phoenix, :LiveView]} | _]}), do: :view
  defp view_kind({:use, _, [_module, :live_component]}), do: :component
  defp view_kind({:use, _, [_module, :live_view]}), do: :view
  defp view_kind(_), do: nil

  defp source_definitions(expressions, file) do
    source_env = %{__ENV__ | file: file, module: nil, aliases: [], macros: [], requires: []}

    {definitions, _env} =
      Enum.flat_map_reduce(expressions, source_env, fn
        {:alias, _, [{:__aliases__, _, parts} = target | options]}, env ->
          {[], source_alias(env, target, parts, List.first(options, []))}

        {:def, meta, [head, [do: _] = body]}, env ->
          case function_head(head) do
            {name, args, guards} ->
              {[{name, args, guards, body, %{env | line: meta[:line]}}], env}

            nil ->
              {[], env}
          end

        _, env ->
          {[], env}
      end)

    definitions
  end

  defp source_alias(env, target, parts, opts) do
    with true <- Keyword.keyword?(opts) and Enum.all?(parts, &is_atom/1),
         module when is_atom(module) <- Macro.expand(target, env),
         {:__aliases__, _, [name]} when is_atom(name) <-
           Keyword.get(opts, :as, {:__aliases__, [], [List.last(parts)]}) do
      name = Module.concat([name])
      %{env | aliases: Keyword.put(env.aliases, name, module)}
    else
      _ -> env
    end
  end

  defp function_head({:when, _, [{name, _, args} | guards]}) when is_list(args),
    do: {name, args, guards}

  defp function_head({name, _, args}) when is_list(args), do: {name, args, []}
  defp function_head({name, _, nil}) when is_atom(name), do: {name, [], []}
  defp function_head(_), do: nil

  defp custom_update?({name, args, _, _, _}) when name in [:update, :update_many] do
    arity = if name == :update, do: 2, else: 1
    minimum = length(args) - Enum.count(args, &match?({:\\, _, _}, &1))
    arity in minimum..length(args)
  end

  defp custom_update?(_), do: false

  defp preserves_kernel_self?({:import, _, [{:__aliases__, _, [:Kernel]}, opts]}) do
    if Keyword.keyword?(opts) do
      case {Keyword.get(opts, :only), Keyword.get(opts, :except, [])} do
        {only, _} when is_list(only) -> {:self, 0} in only
        {:macros, _} -> false
        {_, except} when is_list(except) -> {:self, 0} not in except
        _ -> false
      end
    else
      false
    end
  end

  defp preserves_kernel_self?({kind, _, [head | _]})
       when kind in [:def, :defp, :defmacro, :defmacrop],
       do: not match?({:self, [], _}, function_head(head))

  defp preserves_kernel_self?(_), do: true

  defp render_source({:def, _, [{:render, _, [_assigns]}, [do: body]]}) do
    case body do
      {:sigil_H, meta, [{:<<>>, _, parts}, []]} when is_list(parts) ->
        if Enum.all?(parts, &is_binary/1) do
          line = meta[:line] || 1
          {Enum.join(parts), if(meta[:delimiter] == "\"\"\"", do: line + 1, else: line)}
        end

      _ ->
        nil
    end
  end

  defp render_source(_), do: nil

  defp helper_definition({:defp, meta, [{name, _, args}, [do: body]]}, file)
       when is_atom(name) and is_list(args),
       do: [{name, args, [], [do: body], file, meta[:line]}]

  defp helper_definition(
         {:defp, meta, [{:when, _, [{name, _, args} | guards]}, [do: body]]},
         file
       )
       when is_atom(name) and is_list(args),
       do: [{name, args, guards, [do: body], file, meta[:line]}]

  defp helper_definition(_, _file), do: []

  defp check_handler(env, event, params, socket, body, {template, render_line}, context) do
    try do
      timer =
        Timer.extract(body, params, socket, env) ||
          ProcessTimer.extract(
            body,
            params,
            socket,
            env,
            context.live_view?,
            context.kernel_self?
          )

      case timer do
        {%{message: _} = spec, timer_line} ->
          ProcessTimer.compile!(spec, context.callbacks, context.helpers, env.file, timer_line)

        {%{patch: _}, _line} ->
          :ok

        nil ->
          {name, args, action} =
            Compiler.action_unchecked!(event, params, socket, body, env.file, env.line)

          expanded = Helpers.expand!(action, context.helpers, env.file, env.line)
          Compiler.validate_action!({name, args, expanded}, env.file, env.line)
      end

      tree = LiveLift.Template.compile_liveview(template, env.file, [event], %{}, render_line)

      if match?({%{patch: _}, _}, timer) do
        {spec, timer_line} = timer
        fields = LiveLift.Component.state_fields(tree, [])

        Timer.validate_target!(
          spec,
          fields,
          context.live_view?,
          context.custom_update?,
          env.file,
          timer_line
        )
      end

      "compatible"
    rescue
      error in ArgumentError -> "blocked: #{Exception.message(error)}"
    end
  end
end
