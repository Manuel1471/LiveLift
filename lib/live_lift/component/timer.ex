defmodule LiveLift.Component.Timer do
  @moduledoc false

  @queue :__live_lift_timers
  @delivery :__live_lift_timer
  @max_delay 60_000
  @max_pending 32

  def extract(
        [do: {:__block__, _, [{{:., _, [mod, :send_update_after]}, meta, args}, result]}],
        params,
        {socket, _, _},
        env
      ) do
    if Macro.expand(mod, env) == Phoenix.LiveView do
      line = Keyword.get(meta, :line, env.line)

      with {name, _, context} when is_atom(name) and is_atom(context) <- params,
           [
             {{:., _, [{{:., _, [{^socket, _, _}, :assigns]}, _, []}, :myself]}, _, []},
             assigns,
             delay
           ] <- args,
           {:noreply, {^socket, _, _}} <- result,
           true <- is_integer(delay) and delay in 0..@max_delay,
           true <- Keyword.keyword?(assigns) and assigns != [],
           patch = Map.new(assigns, fn {key, value} -> {key, scalar(value)} end),
           false <- :unsupported in Map.values(patch),
           true <- length(assigns) == map_size(patch) and map_size(patch) <= 8 do
        try do
          LiveLift.State.validate!(patch)
        rescue
          error in ArgumentError -> error!(env.file, line, Exception.message(error))
        end

        {%{delay: delay, patch: patch}, line}
      else
        _ ->
          error!(
            env.file,
            line,
            "use a plain params argument, socket.assigns.myself, up to eight literal scalar assigns and a literal delay from 0 to #{@max_delay} ms, then return {:noreply, socket}"
          )
      end
    end
  end

  def extract(_body, _params, _socket, _env), do: nil

  def validate!(%{patch: _} = timer, fields, env, line) do
    custom_update? =
      Module.defines?(env.module, {:update, 2}, :def) or
        Module.defines?(env.module, {:update_many, 1}, :def)

    validate_target!(
      timer,
      fields,
      Phoenix.LiveView in (Module.get_attribute(env.module, :behaviour) || []),
      custom_update?,
      env.file,
      line
    )
  end

  def validate!(%{message: _}, _fields, _env, _line), do: :ok

  def validate_target!(%{patch: patch}, fields, live_view?, custom_update?, file, line) do
    if live_view? do
      error!(file, line, "use Process.send_after/3 to schedule a callback on the LiveView itself")
    end

    if custom_update? do
      error!(file, line, "the component must use Phoenix's default update callback")
    end

    unless Enum.all?(Map.keys(patch), fn key ->
             key in fields and key not in [:id, :myself] and
               not String.starts_with?(Atom.to_string(key), "__")
           end) do
      error!(file, line, "assign only fields used in the client template or handlers")
    end
  end

  def schedule(socket, event, seq, %{delay: delay} = spec) do
    timers = timers(socket.assigns)

    if map_size(timers) >= @max_pending do
      {:noreply, socket}
    else
      id = Map.get(socket.assigns, :__live_lift_revision, 0) + 1
      token = make_ref()
      effect = Map.take(spec, [:message, :patch])
      timer = %{token: token, event: event, seq: seq, due: now() + delay, effect: effect}

      send_delivery(socket, effect, id, token, delay)
      {:noreply, Phoenix.Component.assign(socket, @queue, Map.put(timers, id, timer))}
    end
  end

  def update(%{@delivery => {id, token}}, socket) when is_reference(token) do
    case take_delivery(socket, id, token) do
      {:ok, %{patch: patch}, updated} -> Phoenix.Component.assign(updated, patch)
      :error -> socket
    end
  end

  def update(assigns, socket), do: Phoenix.Component.assign(socket, assigns)

  def take_delivery(socket, id, token) do
    timers = timers(socket.assigns)

    case Map.get(timers, id) do
      %{token: ^token, effect: effect} ->
        {:ok, effect, Phoenix.Component.assign(socket, @queue, Map.delete(timers, id))}

      _ ->
        :error
    end
  end

  defp send_delivery(_socket, %{message: _}, id, token, delay),
    do: Process.send_after(self(), {@delivery, id, token}, delay)

  defp send_delivery(socket, %{patch: _}, id, token, delay),
    do:
      Phoenix.LiveView.send_update_after(
        socket.assigns.myself,
        %{@delivery => {id, token}},
        delay
      )

  def snapshot(assigns) do
    time = now()

    for {id, %{event: event, seq: seq, due: due}} <- Enum.sort(timers(assigns)),
        do: %{id: id, event: event, seq: seq, remaining: max(due - time, 0)}
  end

  def timers(assigns), do: Map.get(assigns, @queue, %{})

  defp now, do: System.monotonic_time(:millisecond)

  defp scalar({:-, _, [value]}) when is_number(value), do: -value

  defp scalar(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: value

  defp scalar(_value), do: :unsupported

  defp error!(file, line, reason) do
    raise ArgumentError,
          "#{file}:#{line}: unsupported @client send_update_after/3: #{reason}; move it to a server handler"
  end
end
