defmodule Mix.Tasks.LiveLift.Test do
  @moduledoc """
  Compares one marked LiveComponent handler in Elixir and generated JavaScript.

      mix live_lift.test MyAppWeb.Counter --event inc --state '{"count":0}'
      mix live_lift.test MyAppWeb.Form --event draft --state '{"draft":null}' --params '{"value":"Hi"}'

  State keys must match the component's client fields. Parameters are flat
  strings, as required by the current native component subset.
  """

  use Mix.Task

  @shortdoc "Checks a marked LiveComponent handler against generated JavaScript"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args, strict: [event: :string, state: :string, params: :string])

    if invalid != [] or length(rest) != 1 or !opts[:event] or !opts[:state],
      do: Mix.raise("usage: mix live_lift.test Module --event NAME --state JSON [--params JSON]")

    Mix.Task.run("app.start")
    module_name = hd(rest)
    module = Module.concat(String.split(module_name, "."))

    unless Code.ensure_loaded?(module) and
             function_exported?(module, :__live_lift_client_actions__, 0) and
             function_exported?(module, :__live_lift_component_fields__, 0) do
      Mix.raise("#{module_name} is not an opted-in LiveLift LiveComponent")
    end

    unless LiveLift.Component.enabled?(module) do
      Mix.raise("#{module_name} has LiveLift disabled; enable it before testing parity")
    end

    event = opts[:event]

    unless Enum.any?(module.__live_lift_client_actions__(), fn {name, _, _} ->
             Atom.to_string(name) == event
           end) do
      Mix.raise("#{module_name} has no marked @client event #{inspect(event)}")
    end

    state = decode_map!(opts[:state], "state")
    params = decode_map!(opts[:params] || "{}", "params")
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

    {output, status} =
      System.cmd("node", ["--input-type=module", "--eval", source], stderr_to_stdout: true)

    if status != 0, do: Mix.raise("generated JavaScript failed: #{String.trim(output)}")

    javascript_state = Jason.decode!(output)
    elixir_state = elixir_state |> Jason.encode!() |> Jason.decode!()

    if javascript_state != elixir_state do
      Mix.raise(
        "Elixir/JavaScript mismatch for #{module_name}.#{event}: " <>
          "Elixir=#{inspect(elixir_state)} JavaScript=#{inspect(javascript_state)}"
      )
    end

    Mix.shell().info("Parity passed: #{module_name}.handle_event(#{inspect(event)})")
  end

  defp decode_map!(json, label) do
    case Jason.decode(json) do
      {:ok, value} when is_map(value) -> value
      _ -> Mix.raise("#{label} must be a JSON object")
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
