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
    template = LiveLift.Template.compile_liveview(source, env.file, events)
    action_tuples = Enum.map(actions, &elem(&1, 1))
    fields = state_fields(template, action_tuples)

    quote do
      @doc false
      def __live_lift_client_actions__, do: unquote(Macro.escape(action_tuples))

      @doc false
      def __live_lift_client_template__, do: unquote(Macro.escape(template))

      @doc false
      def __live_lift_template_source__, do: {unquote(env.file), unquote(line)}

      @doc false
      def __live_lift_component_fields__, do: unquote(fields)

      defoverridable render: 1

      def render(var!(assigns)) do
        inner = super(var!(assigns))

        if LiveLift.Component.enabled?(__MODULE__) do
          state = LiveLift.Component.state!(var!(assigns), __live_lift_component_fields__())

          var!(assigns) =
            var!(assigns)
            |> Phoenix.Component.assign(:live_lift_inner, inner)
            |> Phoenix.Component.assign(:live_lift_state_json, Jason.encode!(state))
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
            unquote(events),
            __live_lift_component_fields__(),
            fn -> super(event, params, socket) end
          )
        end
      end
    end
  end

  @doc false
  def handle_marked_or_server(event, params, socket, events, fields, original) do
    if event in events do
      sequence = LiveLift.Component.sequence!(params)
      previous = Map.get(socket.assigns, :__live_lift_ack_seq, 0)

      if sequence > 0 and sequence <= previous do
        LiveLift.Component.acknowledge_duplicate(socket, fields)
      else
        result = original.()
        LiveLift.Component.reply!(result, sequence, fields)
      end
    else
      result = original.()
      LiveLift.Component.sync_unmarked(result, socket, fields)
    end
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
    |> collect_fields(action_fields)
    |> Enum.uniq()
    |> Enum.map(&String.to_atom/1)
  end

  defp collect_fields(%{type: "path", root: "state", fields: [field | _]}, acc),
    do: [field | acc]

  defp collect_fields(map, acc) when is_map(map) do
    Enum.reduce(Map.values(map), acc, &collect_fields/2)
  end

  defp collect_fields(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_fields/2)
  defp collect_fields(_value, acc), do: acc

  @doc false
  def state!(assigns, fields) do
    state = Map.new(fields, fn field -> {field, Map.fetch!(assigns, field)} end)
    LiveLift.State.validate!(state)
  end

  @doc false
  def sequence!(params) when is_map(params) do
    event_params = Map.delete(params, "_live_lift_seq")

    if map_size(event_params) > 64,
      do: raise(ArgumentError, "LiveLift event parameter limit exceeded")

    bytes =
      Enum.reduce(event_params, 0, fn {key, value}, total ->
        unless is_binary(key) and Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, key) and
                 key not in ~w(__proto__ constructor prototype) do
          raise ArgumentError, "unsafe LiveLift event parameter: #{inspect(key)}"
        end

        unless is_binary(value) and String.valid?(value),
          do: raise(ArgumentError, "unsupported LiveLift event parameter: #{key}")

        total + byte_size(key) + byte_size(value)
      end)

    if bytes > 65_536,
      do: raise(ArgumentError, "LiveLift event parameter size limit exceeded")

    seq = Map.get(params, "_live_lift_seq", 0)

    unless is_integer(seq) and seq >= 0 and seq <= 9_007_199_254_740_991 do
      raise ArgumentError, "invalid LiveLift event sequence"
    end

    seq
  end

  def sequence!(_params), do: raise(ArgumentError, "LiveLift event params must be a map")

  @doc false
  def reply!({:noreply, socket}, seq, fields) do
    revision = Map.get(socket.assigns, :__live_lift_revision, 0) + 1

    socket =
      socket
      |> Phoenix.Component.assign(:__live_lift_revision, revision)
      |> Phoenix.Component.assign(:__live_lift_ack_seq, seq)

    state = state!(socket.assigns, fields)
    {:reply, %{revision: revision, ack_seq: seq, state: state}, socket}
  end

  def reply!(_result, _seq, _fields) do
    raise ArgumentError, "@client handle_event/3 must return {:noreply, socket}"
  end

  @doc false
  def acknowledge_duplicate(socket, fields) do
    state = state!(socket.assigns, fields)

    {:reply,
     %{
       revision: Map.get(socket.assigns, :__live_lift_revision, 0),
       ack_seq: Map.get(socket.assigns, :__live_lift_ack_seq, 0),
       state: state
     }, socket}
  end

  @doc false
  def sync_unmarked({:noreply, next} = result, previous, fields) do
    if state!(next.assigns, fields) == state!(previous.assigns, fields) do
      result
    else
      revision = Map.get(next.assigns, :__live_lift_revision, 0) + 1
      {:noreply, Phoenix.Component.assign(next, :__live_lift_revision, revision)}
    end
  end

  def sync_unmarked(result, _previous, _fields), do: result
end
