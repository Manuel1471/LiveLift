defmodule LiveLift.Component do
  @moduledoc false

  def on_definition(env, :def, :render, [_assigns], _guards, body) do
    if Module.get_attribute(env.module, :client) == true do
      raise ArgumentError,
            "#{env.file}:#{env.line}: @client must precede handle_event/3, not render/1"
    end

    Module.put_attribute(env.module, :live_lift_render, body)
  end

  def on_definition(env, :def, :handle_event, [event, params, socket], guards, body) do
    if Module.get_attribute(env.module, :client) == true do
      unless is_binary(event) and guards == [] do
        raise ArgumentError,
              "#{env.file}:#{env.line}: @client requires a literal event name and no guard; move this handler to the server"
      end

      action =
        LiveLift.Component.Compiler.action!(event, params, socket, body, env.file, env.line)

      Module.put_attribute(env.module, :live_lift_marked_actions, {event, action})
    end

    Module.delete_attribute(env.module, :client)
  end

  def on_definition(env, kind, name, [_assigns], guards, body)
      when kind in [:def, :defp] and is_atom(name) do
    if Module.get_attribute(env.module, :client) == true do
      raise ArgumentError,
            "#{env.file}:#{env.line}: @client must precede handle_event/3, not #{name}; move this handler to the server"
    end

    if guards == [] and match?([do: {:sigil_H, _, _}], body) do
      Module.put_attribute(
        env.module,
        :live_lift_local_components,
        {Atom.to_string(name), body, env.file, env.line}
      )
    end
  end

  def on_definition(env, _kind, name, _args, _guards, _body) do
    if Module.get_attribute(env.module, :client) == true do
      raise ArgumentError,
            "#{env.file}:#{env.line}: @client must precede handle_event/3, not #{name}; move this handler to the server"
    end
  end

  defmacro __before_compile__(env) do
    actions = env.module |> Module.get_attribute(:live_lift_marked_actions) |> Enum.reverse()
    events = Enum.map(actions, &elem(&1, 0))
    render = Module.get_attribute(env.module, :live_lift_render)

    local_components =
      env.module
      |> Module.get_attribute(:live_lift_local_components)
      |> Enum.reverse()
      |> Enum.reduce(%{}, fn {name, body, file, line}, acc ->
        if Map.has_key?(acc, name) do
          raise ArgumentError,
                "#{file}:#{line}: client function component .#{name} has multiple clauses; move it to the server"
        end

        {source, _} = render_source!(body, file)
        Map.put(acc, name, %{source: source, file: file, line: line})
      end)

    if Module.get_attribute(env.module, :client) == true do
      raise ArgumentError,
            "#{env.file}: @client must precede handle_event/3; no handler followed the marker"
    end

    if actions == [] do
      raise ArgumentError,
            "#{env.file}: use LiveLift requires at least one @client handle_event/3"
    end

    if length(events) != length(Enum.uniq(events)) do
      raise ArgumentError,
            "#{env.file}: @client requires one handler clause per event; move extra clauses to the server"
    end

    {source, line} = render_source!(render, env.file)
    template = LiveLift.Template.compile_liveview(source, env.file, events, local_components)
    action_tuples = Enum.map(actions, &elem(&1, 1))
    fields = state_fields(template, action_tuples)
    optional_fields = optional_state_fields(action_tuples)

    quote do
      @doc false
      def __live_lift_client_actions__, do: unquote(Macro.escape(action_tuples))

      @doc false
      def __live_lift_client_template__, do: unquote(Macro.escape(template))

      @doc false
      def __live_lift_template_source__, do: {unquote(env.file), unquote(line)}

      @doc false
      def __live_lift_component_fields__, do: unquote(fields)

      @doc false
      def __live_lift_component_optional_fields__, do: unquote(optional_fields)

      defoverridable render: 1

      def render(var!(assigns)) do
        inner = super(var!(assigns))

        if LiveLift.Component.enabled?(__MODULE__) do
          state =
            LiveLift.Component.state!(
              var!(assigns),
              __live_lift_component_fields__(),
              __live_lift_component_optional_fields__()
            )

          var!(assigns) =
            var!(assigns)
            |> Phoenix.Component.assign(:live_lift_inner, inner)
            |> Phoenix.Component.assign(
              :live_lift_state_json,
              state |> LiveLift.FloatWire.encode() |> Jason.encode!()
            )
            |> Phoenix.Component.assign(
              :live_lift_revision,
              Map.get(var!(assigns), :__live_lift_revision, 0)
            )
            |> Phoenix.Component.assign(
              :live_lift_ack_seq,
              Map.get(var!(assigns), :__live_lift_ack_seq, 0)
            )

          ~H"""
          <div
            id={@id}
            phx-hook="LiveLift"
            phx-update="ignore"
            data-live-lift-mode="component"
            data-live-lift-module={inspect(__MODULE__)}
            data-live-lift-state={@live_lift_state_json}
            data-live-lift-server-fields="[]"
            data-live-lift-server-revision={@live_lift_revision}
            data-live-lift-ack-seq={@live_lift_ack_seq}
          >{@live_lift_inner}</div>
          """
        else
          inner
        end
      end

      defoverridable handle_event: 3

      def handle_event(event, params, socket) do
        if not LiveLift.Component.enabled?(__MODULE__) do
          result = super(event, params, socket)
          LiveLift.Component.disabled_reply(result, event, params, unquote(events))
        else
          LiveLift.Component.handle_marked_or_server(
            event,
            params,
            socket,
            __MODULE__,
            unquote(events),
            __live_lift_component_fields__(),
            __live_lift_component_optional_fields__(),
            fn -> super(event, params, socket) end
          )
        end
      end
    end
  end

  @doc false
  def handle_marked_or_server(
        event,
        params,
        socket,
        component,
        events,
        fields,
        optional,
        original
      ) do
    marked? = event in events
    started = System.monotonic_time()

    try do
      {result, outcome} =
        if marked? do
          sequence = LiveLift.Component.sequence!(params)
          previous = Map.get(socket.assigns, :__live_lift_ack_seq, 0)

          if sequence > 0 and sequence <= previous do
            {LiveLift.Component.acknowledge_duplicate(socket, fields, optional), :duplicate}
          else
            result = original.()
            {LiveLift.Component.reply!(result, sequence, fields, optional), :ok}
          end
        else
          result = original.()
          {LiveLift.Component.sync_unmarked(result, socket, fields, optional), :ok}
        end

      emit_event(started, component, event, marked?, outcome)
      result
    rescue
      error ->
        emit_event(started, component, event, marked?, :error)
        reraise error, __STACKTRACE__
    end
  end

  defp emit_event(started, component, event, marked?, outcome) do
    :telemetry.execute(
      [:live_lift, :component, :event],
      %{duration: System.monotonic_time() - started},
      %{component: component, event: event, marked?: marked?, outcome: outcome}
    )
  end

  @doc false
  def enabled?(module) do
    Application.get_env(:live_lift, :enabled, true) != false and
      module not in Application.get_env(:live_lift, :disabled_components, [])
  end

  @doc false
  def disabled_reply({:noreply, socket} = result, event, params, events) do
    if event in events and sequence!(params) > 0 do
      {:reply, %{disabled: true}, socket}
    else
      result
    end
  end

  def disabled_reply(result, _event, _params, _events), do: result

  defp render_source!([do: {:sigil_H, meta, [{:<<>>, _, parts}, []]}], file)
       when is_list(parts) do
    if Enum.all?(parts, &is_binary/1) do
      {Enum.join(parts), meta[:line] || 1}
    else
      raise ArgumentError,
            "#{file}:#{meta[:line]}: @client requires a literal ~H render; move dynamic template construction to the server"
    end
  end

  defp render_source!(_body, file) do
    raise ArgumentError,
          "#{file}: @client requires render/1 to return a literal ~H template; move delegated rendering to the server"
  end

  defp state_fields(tree, actions) do
    action_fields =
      Enum.flat_map(actions, fn {_name, _arg, body} ->
        {_body, fields} =
          Macro.prewalk(body, [], fn
            {{:., _, [{:state, _, _}, field]}, _, []} = node, acc when is_atom(field) ->
              {node, [Atom.to_string(field) | acc]}

            node, acc ->
              {node, acc}
          end)

        fields
      end)

    tree
    |> collect_fields(
      action_fields ++ Enum.map(optional_state_fields(actions), &Atom.to_string/1)
    )
    |> Enum.uniq()
    |> Enum.map(&String.to_atom/1)
  end

  defp optional_state_fields(actions) do
    actions
    |> Enum.flat_map(fn {_name, _arg, body} ->
      {_body, fields} =
        Macro.prewalk(body, [], fn
          {:__live_lift_assign_new__, _, [_source, field, _fallback]} = node, acc
          when is_atom(field) ->
            {node, [field | acc]}

          node, acc ->
            {node, acc}
        end)

      fields
    end)
    |> Enum.uniq()
  end

  defp collect_fields(%{type: "path", root: "state", fields: [field | _]}, acc),
    do: [field | acc]

  defp collect_fields(map, acc) when is_map(map) do
    Enum.reduce(Map.values(map), acc, &collect_fields/2)
  end

  defp collect_fields(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_fields/2)
  defp collect_fields(_value, acc), do: acc

  @doc false
  def state!(assigns, fields, optional \\ []) do
    state =
      Enum.reduce(fields, %{}, fn field, acc ->
        case Map.fetch(assigns, field) do
          {:ok, value} -> Map.put(acc, field, value)
          :error -> if field in optional, do: acc, else: Map.fetch!(assigns, field)
        end
      end)

    LiveLift.State.validate!(state)
  end

  @doc false
  def sequence!(params) when is_map(params) do
    event_params = Map.delete(params, "_live_lift_seq")
    validate_event_params!(event_params, 0, {0, 0})

    seq = Map.get(params, "_live_lift_seq", 0)

    unless is_integer(seq) and seq >= 0 and seq <= 9_007_199_254_740_991 do
      raise ArgumentError, "invalid LiveLift event sequence"
    end

    seq
  end

  def sequence!(_params), do: raise(ArgumentError, "LiveLift event params must be a map")

  defp validate_event_params!(params, depth, budget) do
    if depth > 0 and map_size(params) == 0,
      do: raise(ArgumentError, "unsupported empty LiveLift event parameter map")

    Enum.reduce(params, budget, fn {key, value}, {fields, bytes} ->
      unless is_binary(key) and Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, key) and
               key not in ~w(__proto__ constructor prototype _live_lift_seq) do
        raise ArgumentError, "unsafe LiveLift event parameter: #{inspect(key)}"
      end

      bytes = bytes + byte_size(key)

      {fields, bytes} =
        cond do
          is_binary(value) and String.valid?(value) ->
            {fields + 1, bytes + byte_size(value)}

          is_map(value) and depth < 3 ->
            validate_event_params!(value, depth + 1, {fields, bytes})

          true ->
            raise ArgumentError, "unsupported LiveLift event parameter: #{key}"
        end

      if fields > 64,
        do: raise(ArgumentError, "LiveLift event parameter limit exceeded")

      if bytes > 65_536,
        do: raise(ArgumentError, "LiveLift event parameter size limit exceeded")

      {fields, bytes}
    end)
  end

  @doc false
  def reply!(result, seq, fields, optional \\ [])

  def reply!({:noreply, socket}, seq, fields, optional) do
    revision = Map.get(socket.assigns, :__live_lift_revision, 0) + 1

    socket =
      socket
      |> Phoenix.Component.assign(:__live_lift_revision, revision)
      |> Phoenix.Component.assign(:__live_lift_ack_seq, seq)

    state = state!(socket.assigns, fields, optional)
    {:reply, %{revision: revision, ack_seq: seq, state: LiveLift.FloatWire.encode(state)}, socket}
  end

  def reply!(_result, _seq, _fields, _optional) do
    raise ArgumentError, "@client handle_event/3 must return {:noreply, socket}"
  end

  @doc false
  def acknowledge_duplicate(socket, fields, optional \\ []) do
    state = state!(socket.assigns, fields, optional)

    {:reply,
     %{
       revision: Map.get(socket.assigns, :__live_lift_revision, 0),
       ack_seq: Map.get(socket.assigns, :__live_lift_ack_seq, 0),
       state: LiveLift.FloatWire.encode(state)
     }, socket}
  end

  @doc false
  def sync_unmarked(result, previous, fields, optional \\ [])

  def sync_unmarked({:noreply, next} = result, previous, fields, optional) do
    if LiveLift.FloatWire.encode(state!(next.assigns, fields, optional)) ==
         LiveLift.FloatWire.encode(state!(previous.assigns, fields, optional)) do
      result
    else
      revision = Map.get(next.assigns, :__live_lift_revision, 0) + 1
      {:noreply, Phoenix.Component.assign(next, :__live_lift_revision, revision)}
    end
  end

  def sync_unmarked(result, _previous, _fields, _optional), do: result
end
