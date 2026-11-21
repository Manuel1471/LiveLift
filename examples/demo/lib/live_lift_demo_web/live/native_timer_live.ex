defmodule LiveLiftDemoWeb.NativeTimerLive do
  use LiveLiftDemoWeb, :live_view
  use LiveLift

  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0)}

  def render(assigns) do
    ~H"""
    <main>
      <h1>LiveView timer</h1>
      <button type="button" phx-click="inc">Add one</button>
      <button type="button" phx-click="schedule">Schedule ten</button>
      <output aria-live="polite">{@count}</output>
    </main>
    """
  end

  @client true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  def handle_event("schedule", _params, socket) do
    Process.send_after(self(), :add_ten, 100)
    {:noreply, socket}
  end

  def handle_info(:add_ten, socket) do
    {:noreply, update(socket, :count, &(&1 + 10))}
  end
end
