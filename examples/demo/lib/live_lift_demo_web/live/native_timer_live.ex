defmodule LiveLiftDemoWeb.NativeTimerLive do
  use LiveLiftDemoWeb, :live_view
  use LiveLift

  alias Phoenix.PubSub

  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0, timer_topic: nil)}

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    count =
      with value when is_binary(value) and byte_size(value) in 1..3 <- params["start"],
           {count, ""} when count in 0..999 <- Integer.parse(value) do
        count
      else
        _ -> 0
      end

    topic = timer_topic(params["room"])

    if connected?(socket) and topic != socket.assigns.timer_topic do
      if previous = socket.assigns.timer_topic,
        do: PubSub.unsubscribe(LiveLiftDemo.PubSub, previous)

      if topic, do: PubSub.subscribe(LiveLiftDemo.PubSub, topic)
    end

    {:noreply, assign(socket, count: count, timer_topic: topic)}
  end

  defp timer_topic(room) when is_binary(room) and byte_size(room) in 1..64 do
    if Regex.match?(~r/\A[a-zA-Z0-9_-]+\z/, room), do: "native-timer:" <> room
  end

  defp timer_topic(_room), do: nil

  def render(assigns) do
    ~H"""
    <main>
      <h1>LiveView timer</h1>
      <button type="button" phx-click="inc">Add one</button>
      <button type="button" phx-click="double">Double</button>
      <button type="button" phx-click="schedule">Schedule ten on server</button>
      <button type="button" phx-click="predict">Schedule ten locally</button>
      <button :if={@timer_topic} type="button" phx-click="broadcast">Add ten in this room</button>
      <button type="button" phx-click="leave">Open component counter</button>
      <output aria-live="polite">{@count}</output>
    </main>
    """
  end

  @client true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  @client true
  def handle_event("double", _params, socket) do
    {:noreply, update(socket, :count, &(&1 * 2))}
  end

  def handle_event("schedule", _params, socket) do
    Process.send_after(self(), :add_ten, 100)
    {:noreply, socket}
  end

  def handle_event("broadcast", _params, socket) do
    if topic = socket.assigns.timer_topic do
      PubSub.broadcast(LiveLiftDemo.PubSub, topic, {:room_add_ten, topic})
    end

    {:noreply, socket}
  end

  def handle_event("leave", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/native-counter")}
  end

  @client true
  def handle_event("predict", _params, socket) do
    Process.send_after(self(), :add_ten, 250)
    {:noreply, socket}
  end

  def handle_info(:add_ten, socket) do
    {:noreply, update(socket, :count, &(&1 + 10))}
  end

  def handle_info({:room_add_ten, topic}, %{assigns: %{timer_topic: topic}} = socket) do
    {:noreply, update(socket, :count, &(&1 + 10))}
  end

  def handle_info({:room_add_ten, _topic}, socket), do: {:noreply, socket}
end
