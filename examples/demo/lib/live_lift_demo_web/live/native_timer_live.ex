defmodule LiveLiftDemoWeb.NativeTimerLive do
  use LiveLiftDemoWeb, :live_view
  use LiveLift

  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0)}

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    count =
      with value when is_binary(value) and byte_size(value) in 1..3 <- params["start"],
           {count, ""} when count in 0..999 <- Integer.parse(value) do
        count
      else
        _ -> 0
      end

    {:noreply, assign(socket, :count, count)}
  end

  def render(assigns) do
    ~H"""
    <main>
      <h1>LiveView timer</h1>
      <button type="button" phx-click="inc">Add one</button>
      <button type="button" phx-click="double">Double</button>
      <button type="button" phx-click="schedule">Schedule ten on server</button>
      <button type="button" phx-click="predict">Schedule ten locally</button>
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
end
