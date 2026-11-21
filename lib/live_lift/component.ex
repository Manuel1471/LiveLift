defmodule LiveLift.Component do
  @moduledoc false

  alias LiveLift.FloatWire
  alias LiveLift.Component.Timer

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

      timer = Timer.extract(body, params, socket, env)

      action =
        if timer do
          {String.to_atom(event), :state, {:state, [], nil}}
        else
          LiveLift.Component.Compiler.action_unchecked!(
            event,
            params,
            socket,
            body,
            env.file,
            env.line
          )
        end

      Module.put_attribute(
        env.module,
        :live_lift_marked_actions,
        {event, action, timer, env.file, env.line}
      )
    end

    Module.delete_attribute(env.module, :client)
  end

  def on_definition(env, kind, name, [assigns_arg], guards, body)
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
    else
      if kind == :defp do
        Module.put_attribute(
          env.module,
          :live_lift_local_helpers,
          {name, [assigns_arg], guards, body, env.file, env.line}
        )
      end
    end
  end

  def on_definition(env, :defp, name, args, guards, body) when is_atom(name) and is_list(args) do
    if Module.get_attribute(env.module, :client) == true do
      raise ArgumentError,
            "#{env.file}:#{env.line}: @client must precede handle_event/3, not #{name}; move this handler to the server"
    end

    Module.put_attribute(
      env.module,
      :live_lift_local_helpers,
      {name, args, guards, body, env.file, env.line}
    )
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
    helpers = env.module |> Module.get_attribute(:live_lift_local_helpers) |> Enum.reverse()

    action_tuples =
      Enum.map(actions, fn {_event, {name, args, body}, _timer, file, line} ->
        expanded = LiveLift.Component.Helpers.expand!(body, helpers, file, line)
        action = {name, args, expanded}
        LiveLift.Component.Compiler.validate_action!(action, file, line)
        action
      end)

    fields = state_fields(template, action_tuples)
    optional_fields = optional_state_fields(action_tuples)

    timers =
      Map.new(
        for {event, _action, {timer, line}, _file, _} <- actions do
          Timer.validate!(timer, fields, env, line)
          {event, timer}
        end
      )

    lifecycle =
      if live_view?(env.module) do
        live_view_wrappers(env.module)
      else
        [component_mount_wrapper(env.module), update_wrapper(env.module, map_size(timers) > 0)]
      end

    event_timer =
      if map_size(timers) > 0,
        do: quote(do: Map.get(__live_lift_component_timers__(), event)),
        else: nil

    quote do
      unquote_splicing(lifecycle)

      @doc false
      def __live_lift_client_actions__, do: unquote(Macro.escape(action_tuples))

      @doc false
      def __live_lift_component_timers__, do: unquote(Macro.escape(timers))

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
              :live_lift_dom_id,
              Map.get(var!(assigns), :__live_lift_dom_id, var!(assigns)[:id])
            )
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
            id={@live_lift_dom_id}
            phx-hook="LiveLift"
            phx-update="ignore"
            data-live-lift-mode="component"
            data-live-lift-module={inspect(__MODULE__)}
            data-live-lift-state={@live_lift_state_json}
            data-live-lift-server-fields="[]"
            data-live-lift-server-revision={@live_lift_revision}
            data-live-lift-ack-seq={@live_lift_ack_seq}
            data-live-lift-instance={Map.get(assigns, :__live_lift_instance)}
            data-live-lift-reconnect-conflict={LiveLift.Component.reconnect_conflict()}
            data-live-lift-timers={LiveLift.Component.timer_snapshot(var!(assigns))}
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
            unquote(event_timer),
            fn -> super(event, params, socket) end
          )
        end
      end
    end
  end

  defp live_view?(module),
    do: Phoenix.LiveView in (Module.get_attribute(module, :behaviour) || [])

  defp component_mount_wrapper(module) do
    if Module.defines?(module, {:mount, 1}, :def) do
      quote do
        defoverridable mount: 1

        def mount(socket) do
          LiveLift.Component.mount_instance(super(socket))
        end
      end
    else
      quote do
        def mount(socket), do: LiveLift.Component.mount_instance({:ok, socket})
      end
    end
  end

  defp live_view_wrappers(module) do
    mount =
      if Module.defines?(module, {:mount, 3}, :def) do
        quote do
          defoverridable mount: 3

          def mount(params, session, socket) do
            LiveLift.Component.mount_view_instance(super(params, session, socket))
          end
        end
      else
        quote do
          def mount(_params, _session, socket) do
            LiveLift.Component.mount_view_instance({:ok, socket})
          end
        end
      end

    callbacks =
      for {callback, args} <- [
            {:handle_info, Macro.generate_arguments(2, __MODULE__)},
            {:handle_params, Macro.generate_arguments(3, __MODULE__)}
          ],
          Module.defines?(module, {callback, length(args)}, :def) do
        quote do
          defoverridable [{unquote(callback), unquote(length(args))}]

          def unquote(callback)(unquote_splicing(args)) do
            LiveLift.Component.sync_view_callback(
              super(unquote_splicing(args)),
              unquote(List.last(args)),
              __MODULE__
            )
          end
        end
      end

    [mount | callbacks]
  end

  defp update_wrapper(module, timed?) do
    cond do
      Module.defines?(module, {:update_many, 1}, :def) ->
        quote do
          defoverridable update_many: 1

          def update_many(entries) do
            LiveLift.Component.sync_updates(super(entries), entries, __MODULE__)
          end
        end

      Module.defines?(module, {:update, 2}, :def) ->
        quote do
          defoverridable update: 2

          def update(assigns, socket) do
            LiveLift.Component.sync_update(super(assigns, socket), socket, __MODULE__)
          end
        end

      true ->
        assign =
          if timed?,
            do: quote(do: LiveLift.Component.Timer.update(assigns, socket)),
            else: quote(do: Phoenix.Component.assign(socket, assigns))

        quote do
          def update(assigns, socket) do
            result = {:ok, unquote(assign)}
            LiveLift.Component.sync_update(result, socket, __MODULE__)
          end
        end
    end
  end

  @doc false
  def sync_update({:ok, %Phoenix.LiveView.Socket{} = next}, previous, module),
    do: {:ok, sync_updated_socket(next, previous, module)}

  def sync_update(result, _previous, _module), do: result

  @doc false
  def sync_updates(results, entries, module)
      when is_list(results) and length(results) == length(entries) do
    Enum.zip_with(results, entries, fn
      %Phoenix.LiveView.Socket{} = next, {_assigns, previous} ->
        sync_updated_socket(next, previous, module)

      other, _entry ->
        other
    end)
  end

  def sync_updates(results, _entries, _module), do: results

  defp sync_updated_socket(next, previous, module) do
    cond do
      not enabled?(module) ->
        next

      not Map.get(previous.assigns, :__live_lift_updated, false) ->
        Phoenix.Component.assign(next, :__live_lift_updated, true)

      true ->
        if changed_projection?(next, previous, module), do: advance_revision(next), else: next
    end
  end

  defp changed_projection?(next, previous, module) do
    fields = module.__live_lift_component_fields__()

    Timer.timers(next.assigns) != Timer.timers(previous.assigns) or
      FloatWire.encode(Map.take(next.assigns, fields)) !==
        FloatWire.encode(Map.take(previous.assigns, fields))
  end

  defp advance_revision(socket) do
    revision = Map.get(socket.assigns, :__live_lift_revision, 0) + 1
    Phoenix.Component.assign(socket, :__live_lift_revision, revision)
  end

  @doc false
  def timer_snapshot(assigns) do
    if Map.has_key?(assigns, :__live_lift_timers), do: Jason.encode!(Timer.snapshot(assigns))
  end

  @doc false
  def mount_instance({:ok, socket}), do: {:ok, put_instance(socket)}

  def mount_instance({:ok, socket, options}), do: {:ok, put_instance(socket), options}

  @doc false
  def mount_view_instance({:ok, socket}), do: {:ok, put_view_instance(socket)}

  def mount_view_instance({:ok, socket, options}), do: {:ok, put_view_instance(socket), options}

  defp put_view_instance(socket),
    do:
      socket
      |> put_instance()
      |> Phoenix.Component.assign(:__live_lift_dom_id, "#{socket.id}-lift")

  @doc false
  def sync_view_callback({:noreply, next} = result, previous, module) do
    if enabled?(module) and changed_projection?(next, previous, module) do
      {:noreply, advance_revision(next)}
    else
      result
    end
  end

  def sync_view_callback(result, _previous, _module), do: result

  defp put_instance(socket) do
    instance = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    Phoenix.Component.assign(socket, :__live_lift_instance, instance)
  end

  @doc false
  def reconnect_conflict do
    case Application.get_env(:live_lift, :reconnect_conflict, :replay_offline) do
      :replay_offline -> "replay_offline"
      :discard -> "discard"
      _ -> raise ArgumentError, "LiveLift reconnect_conflict must be :replay_offline or :discard"
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
        timer,
        original
      ) do
    marked? = event in events
    started = System.monotonic_time()

    try do
      {result, outcome} =
        if marked? do
          sequence = LiveLift.Component.sequence!(params)
          previous = Map.get(socket.assigns, :__live_lift_ack_seq, 0)

          cond do
            sequence > 0 and sequence <= previous ->
              {LiveLift.Component.acknowledge_duplicate(socket, fields, optional), :duplicate}

            sequence > previous + 1 ->
              {:reply, snapshot, ^socket} =
                LiveLift.Component.acknowledge_duplicate(socket, fields, optional)

              {{:reply, Map.put(snapshot, :expected_seq, previous + 1), socket}, :gap}

            true ->
              result =
                if timer, do: Timer.schedule(socket, event, sequence, timer), else: original.()

              ack = if sequence == 0, do: previous, else: sequence
              {LiveLift.Component.reply!(result, ack, fields, optional), :ok}
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
    reply = %{revision: revision, ack_seq: seq, state: LiveLift.FloatWire.encode(state)}
    {:reply, with_timers(reply, socket), socket}
  end

  def reply!(_result, _seq, _fields, _optional) do
    raise ArgumentError, "@client handle_event/3 must return {:noreply, socket}"
  end

  @doc false
  def acknowledge_duplicate(socket, fields, optional \\ []) do
    state = state!(socket.assigns, fields, optional)

    reply = %{
      revision: Map.get(socket.assigns, :__live_lift_revision, 0),
      ack_seq: Map.get(socket.assigns, :__live_lift_ack_seq, 0),
      state: LiveLift.FloatWire.encode(state)
    }

    {:reply, with_timers(reply, socket), socket}
  end

  defp with_timers(reply, socket) do
    if Map.has_key?(socket.assigns, :__live_lift_timers),
      do: Map.put(reply, :timers, Timer.snapshot(socket.assigns)),
      else: reply
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
