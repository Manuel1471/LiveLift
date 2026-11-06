defmodule LiveLiftDemoWeb.CounterLive do
  use LiveLiftDemoWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, server_count: 0)}
  end

  def render(assigns) do
    ~H"""
    <main style="max-width: 36rem; margin: 4rem auto; font: 1.2rem system-ui;">
      <h1>LiveLift demo</h1>
      <p>This UI is written by the app. Its Elixir actions run in your browser.</p>
      <section
        id="local-counter"
        phx-hook="LiveLift"
        phx-update="ignore"
        data-live-lift-state={Jason.encode!(%{count: 10, step: 2})}
      >
        <h2>Custom score</h2>
        <button type="button" data-live-lift-action="retreat">Subtract step</button>
        <output data-live-lift-text="count" aria-live="polite">10</output>
        <button type="button" data-live-lift-action="advance">Add step</button>
        <p>Step: <span data-live-lift-text="step">2</span></p>
      </section>

      <p>The second counter is handled by Phoenix LiveView on the server.</p>
      <button id="server-increment" phx-click="server_increment" type="button">
        Server count: {@server_count}
      </button>

      <p>Try changing both values. A server render should preserve the local score.</p>
    </main>
    """
  end

  def handle_event("server_increment", _params, socket) do
    {:noreply, update(socket, :server_count, &(&1 + 1))}
  end
end
