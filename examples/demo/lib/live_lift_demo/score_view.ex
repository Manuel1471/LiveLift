defmodule LiveLiftDemo.ScoreView do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <section class="client-panel" aria-label="Client-side score" title="Score &amp; activity">
      <div class="panel-topline">
        <span class="eyebrow"><span class="status-dot"></span> CLIENT / ELIXIR</span>
        <span class="runtime-pill">Instant interaction</span>
      </div>
      <div class="panel-heading">
        <div>
          <h2>Local score</h2>
          <p>Actions compiled from <code>@client :local</code> run in your browser.</p>
        </div>
        <div class="mini-icon" aria-hidden="true">↗</div>
      </div>
      <div class="score-row">
        <output aria-live="polite" class={@tone}>{@count}</output>
        <div class="score-meta"><span>points</span><span>+{@step} per click</span></div>
      </div>
      <div class="chart-head"><span>Progress to 20</span><strong>{@count} / 20</strong></div>
      <progress value={@count} max="20" title={@title} aria-label="Local score progress"></progress>
      <div class="chart-scale">
        <span>0</span><span>5</span><span>10</span><span>15</span><span>20</span>
      </div>
      <p :if={@milestone} class="milestone-note">✦ Milestone reached at 12</p>
      <div class="client-actions">
        <button
          type="button"
          class="button-quiet"
          phx-click="retreat"
          phx-target={@myself}
          aria-label="− 2 points"
        >− 2</button>
        <button
          type="button"
          class="button-primary"
          phx-click="advance"
          phx-target={@myself}
          aria-label="+ 2 points"
        >+ 2 points <span aria-hidden="true">↗</span></button>
        <button type="button" class="button-quiet" phx-click="reset" phx-target={@myself}>Reset</button>
      </div>
      <div class="panel-divider"></div>
      <div class="sync-row">
        <div>
          <strong>Send this value to LiveView</strong><span>Explicit bridge through
          <code>handle_event/3</code></span>
        </div>
        <button
          type="button"
          class="button-sync"
          phx-click="save_score"
          phx-target={@myself}
          phx-value-count={@count}
          phx-value-revision={@sync_revision}
        >Sync score <span aria-hidden="true">→</span></button>
      </div>
      <p class="milestone-note" aria-live="polite">
        Server saved: {@saved_score} · Server events: {@server_total}
      </p>
    </section>
    """
  end

  @client :local
  def handle_event("advance", _params, socket) do
    {:noreply,
     socket
     |> assign(:count, socket.assigns.count + socket.assigns.step)
     |> assign(
       :tone,
       if(socket.assigns.count + socket.assigns.step == 12, do: "milestone", else: "regular")
     )
     |> assign(:milestone, socket.assigns.count + socket.assigns.step == 12)}
  end

  @client :local
  def handle_event("retreat", _params, socket) do
    {:noreply,
     socket
     |> assign(:count, socket.assigns.count - socket.assigns.step)
     |> assign(:tone, "regular")
     |> assign(:milestone, false)}
  end

  @client :local
  def handle_event("reset", _params, socket) do
    {:noreply,
     socket |> assign(:count, 10) |> assign(:tone, "regular") |> assign(:milestone, false)}
  end

  def handle_event("save_score", params, socket) do
    send(self(), {:save_score, params})
    {:noreply, socket}
  end
end
