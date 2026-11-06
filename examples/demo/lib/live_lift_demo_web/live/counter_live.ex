defmodule LiveLiftDemoWeb.CounterLive do
  use LiveLiftDemoWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, server_count: 0)}
  end

  def render(assigns) do
    ~H"""
    <main style="max-width: 36rem; margin: 4rem auto; font: 1.2rem system-ui;">
      <h1>LiveLift demo</h1>
      <p>The first counter runs in your browser, without a server event.</p>
      <LiveLift.Counter.counter id="local-counter" initial={10} />

      <p>The second counter is handled by Phoenix LiveView on the server.</p>
      <button id="server-increment" phx-click="server_increment" type="button">
        Server count: {@server_count}
      </button>

      <p>Try changing both counters. A server render should preserve the local count.</p>
    </main>
    """
  end

  def handle_event("server_increment", _params, socket) do
    {:noreply, update(socket, :server_count, &(&1 + 1))}
  end
end
