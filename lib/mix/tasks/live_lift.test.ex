defmodule Mix.Tasks.LiveLift.Test do
  @moduledoc """
  Compares marked LiveComponent handlers in Elixir and generated JavaScript.

      mix live_lift.test MyAppWeb.Counter --event inc --state '{"count":0}'
      mix live_lift.test MyAppWeb.Form --event draft --state '{"draft":null}' --params '{"value":"Hi"}'
      mix live_lift.test --cases test/live_lift_cases.json

  State keys must match the component's client fields. Parameters are flat
  strings, as required by the current native component subset. A cases file is
  a nonempty JSON array of objects with `module`, `event`, `state`, and optional
  `params`. Every marked event of each listed module needs at least one case.
  The cases file must also include every opted-in component in the current app.
  """

  use Mix.Task

  @shortdoc "Checks a marked LiveComponent handler against generated JavaScript"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [event: :string, state: :string, params: :string, cases: :string]
      )

    if invalid != [] or not valid_arguments?(opts, rest), do: Mix.raise(usage())

    Mix.Task.run("app.start")

    if path = opts[:cases] do
      cases = read_cases!(path)

      covered =
        Enum.reduce(cases, %{}, fn entry, acc ->
          {module, event} = run_case_from_file!(entry, path)
          Map.update(acc, module, MapSet.new([event]), &MapSet.put(&1, event))
        end)

      for {module, events} <- covered do
        marked =
          MapSet.new(module.__live_lift_client_actions__(), fn {name, _, _} ->
            Atom.to_string(name)
          end)

        missing = marked |> MapSet.difference(events) |> MapSet.to_list() |> Enum.sort()

        if missing != [] do
          Mix.raise(
            "#{inspect(module)} has marked events without cases: #{Enum.join(missing, ", ")}"
          )
        end
      end

      app = Mix.Project.config()[:app]

      app_components =
        (Application.spec(app, :modules) || [])
        |> Enum.filter(fn module ->
          Code.ensure_loaded?(module) and
            function_exported?(module, :__live_lift_component_fields__, 0) and
            function_exported?(module, :__live_lift_client_actions__, 0)
        end)
        |> MapSet.new()

      missing_modules =
        app_components
        |> MapSet.difference(MapSet.new(Map.keys(covered)))
        |> MapSet.to_list()
        |> Enum.sort()

      if missing_modules != [] do
        Mix.raise(
          "app has opted-in components without parity cases: " <>
            Enum.map_join(missing_modules, ", ", &inspect/1)
        )
      end

      Mix.shell().info("#{length(cases)} parity cases passed across #{map_size(covered)} modules")
    else
      state = decode_map!(opts[:state], "state")
      params = decode_map!(opts[:params] || "{}", "params")
      run_case!(hd(rest), opts[:event], state, params)
      :ok
    end
  end

  defp valid_arguments?(opts, rest) do
    if opts[:cases] do
      rest == [] and is_nil(opts[:event]) and is_nil(opts[:state]) and is_nil(opts[:params])
    else
      length(rest) == 1 and is_binary(opts[:event]) and is_binary(opts[:state])
    end
  end

  defp usage do
    "usage: mix live_lift.test Module --event NAME --state JSON [--params JSON] " <>
      "or mix live_lift.test --cases PATH"
  end

  defp read_cases!(path) do
    with {:ok, json} <- File.read(path),
         {:ok, cases} when is_list(cases) and cases != [] <- Jason.decode(json) do
      cases
    else
      _ -> Mix.raise("#{path} must contain a nonempty JSON array of parity cases")
    end
  end

  defp run_case_from_file!(entry, path) do
    case entry do
      %{"module" => module, "event" => event, "state" => state} = case_data
      when is_binary(module) and is_binary(event) and is_map(state) ->
        params = Map.get(case_data, "params", %{})

        unless is_map(params), do: Mix.raise("#{path}: params must be a JSON object")
        run_case!(module, event, state, params)

      _ ->
        Mix.raise("#{path}: every case needs module, event, and state object")
    end
  end

  defp run_case!(module_name, event, state, params) do
    module = Module.concat(String.split(module_name, "."))

    unless Code.ensure_loaded?(module) and
             function_exported?(module, :__live_lift_client_actions__, 0) and
             function_exported?(module, :__live_lift_component_fields__, 0) do
      Mix.raise("#{module_name} is not an opted-in LiveLift LiveComponent")
    end

    unless LiveLift.Component.enabled?(module) do
      Mix.raise("#{module_name} has LiveLift disabled; enable it before testing parity")
    end

    unless Enum.any?(module.__live_lift_client_actions__(), fn {name, _, _} ->
             Atom.to_string(name) == event
           end) do
      Mix.raise("#{module_name} has no marked @client event #{inspect(event)}")
    end

    fields = module.__live_lift_component_fields__()
    expected_keys = MapSet.new(fields, &Atom.to_string/1)

    if MapSet.new(Map.keys(state)) != expected_keys do
      Mix.raise("state keys must be exactly: #{Enum.map_join(fields, ", ", &Atom.to_string/1)}")
    end

    LiveLift.Component.sequence!(Map.put(params, "_live_lift_seq", 1))

    client_state =
      Map.new(fields, fn field ->
        {field, state |> Map.fetch!(Atom.to_string(field)) |> restore_state_keys!()}
      end)

    LiveLift.State.validate!(client_state)
    assigns = Map.merge(client_state, %{id: "live-lift-parity", __changed__: %{}})

    socket = %Phoenix.LiveView.Socket{assigns: assigns}

    {:reply, %{state: elixir_state}, _socket} =
      module.handle_event(event, Map.put(params, "_live_lift_seq", 1), socket)

    source =
      LiveLift.Client.Compiler.compile_module(module) <>
        "\nconsole.log(JSON.stringify(actions[#{Jason.encode!(event)}](#{Jason.encode!(state)}, {params: #{Jason.encode!(params)}, value: null, checked: false})));\n"

    output = run_javascript!(source)

    javascript_state = Jason.decode!(output)
    elixir_state = elixir_state |> Jason.encode!() |> Jason.decode!()

    if javascript_state != elixir_state do
      Mix.raise(
        "Elixir/JavaScript mismatch for #{module_name}.#{event}: " <>
          "Elixir=#{inspect(elixir_state)} JavaScript=#{inspect(javascript_state)}"
      )
    end

    Mix.shell().info("Parity passed: #{module_name}.handle_event(#{inspect(event)})")
    {module, event}
  end

  defp decode_map!(json, label) do
    case Jason.decode(json) do
      {:ok, value} when is_map(value) -> value
      _ -> Mix.raise("#{label} must be a JSON object")
    end
  end

  defp run_javascript!(source) do
    path =
      Path.join(
        System.tmp_dir!(),
        "live_lift_parity_#{System.unique_integer([:positive])}.mjs"
      )

    try do
      File.write!(path, source)
      {output, status} = System.cmd("node", [path], stderr_to_stdout: true)
      if status != 0, do: Mix.raise("generated JavaScript failed: #{String.trim(output)}")
      output
    after
      File.rm(path)
    end
  end

  defp restore_state_keys!(value) when is_list(value),
    do: Enum.map(value, &restore_state_keys!/1)

  defp restore_state_keys!(value) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      unless Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, key) and
               key not in ~w(__proto__ constructor prototype) do
        Mix.raise("unsafe nested state key: #{inspect(key)}")
      end

      atom =
        try do
          String.to_existing_atom(key)
        rescue
          ArgumentError -> Mix.raise("nested state key #{inspect(key)} is not an existing atom")
        end

      {atom, restore_state_keys!(nested)}
    end)
  end

  defp restore_state_keys!(value), do: value
end
