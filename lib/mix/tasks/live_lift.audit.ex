defmodule Mix.Tasks.LiveLift.Audit do
  @moduledoc """
  Reports which LiveComponent handlers fit LiveLift's current client subset.

      mix live_lift.audit
      mix live_lift.audit --path lib/my_app_web

  This is a source audit. It does not modify files or mark handlers for the
  client. A compatible result still needs normal tests and a browser check.
  """

  use Mix.Task

  @shortdoc "Reports client-compatible LiveComponent handlers"

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

    if Enum.any?(expressions, &live_component_use?/1) do
      template = Enum.find_value(expressions, &render_source/1)

      handlers =
        for {:def, meta, [{:handle_event, _, [event, params, socket]}, [do: result]]} <-
              expressions,
            do: {meta[:line], event, params, socket, result}

      duplicates =
        handlers
        |> Enum.map(&elem(&1, 1))
        |> Enum.frequencies()

      for {line, event, params, socket, result} <- handlers do
        status =
          cond do
            not is_binary(event) ->
              "blocked: use a literal event name or keep this handler on the server"

            Map.get(duplicates, event) > 1 ->
              "blocked: multiple clauses for this event; keep it on the server"

            template == nil ->
              "blocked: render/1 must return a literal ~H template"

            true ->
              check_handler(file, line, event, params, socket, result, template)
          end

        {file, line, name, event, status}
      end
    else
      []
    end
  end

  defp live_component_use?({:use, _, [{:__aliases__, _, [:Phoenix, :LiveComponent]}]}), do: true
  defp live_component_use?({:use, _, [_module, :live_component]}), do: true
  defp live_component_use?(_), do: false

  defp render_source({:def, _, [{:render, _, [_assigns]}, [do: body]]}) do
    case body do
      {:sigil_H, meta, [{:<<>>, _, parts}, []]} when is_list(parts) ->
        if Enum.all?(parts, &is_binary/1), do: {Enum.join(parts), meta[:line] || 1}

      _ ->
        nil
    end
  end

  defp render_source(_), do: nil

  defp check_handler(file, line, event, params, socket, result, {template, render_line}) do
    try do
      LiveLift.Component.Compiler.action!(event, params, socket, [do: result], file, line)
      source = String.duplicate("\n", max(render_line - 1, 0)) <> template
      LiveLift.Template.compile_liveview(source, file, [event])
      "compatible"
    rescue
      error in ArgumentError -> "blocked: #{Exception.message(error)}"
    end
  end
end
