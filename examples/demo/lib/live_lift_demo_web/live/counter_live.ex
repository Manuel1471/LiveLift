defmodule LiveLiftDemoWeb.CounterLive do
  use LiveLiftDemoWeb, :live_view

  def mount(params, _session, socket) do
    task_items =
      if params["bench_rows"] == "1000" do
        Enum.map(1..1_000, &%{id: &1, name: "Task #{&1}"})
      else
        [%{id: 1, name: "Write Elixir"}, %{id: 2, name: "Ship a component"}]
      end

    {:ok,
     assign(socket,
       server_count: 0,
       server_history: [0],
       saved_score: nil,
       sync_revision: 0,
       task_items: task_items
     )}
  end

  def render(assigns) do
    ~H"""
    <main class="demo-shell">
      <header class="site-header">
        <a href="/" class="brand"><span class="brand-mark" aria-hidden="true">L<span>↗</span></span><span>LiveLift<span class="brand-period">.</span></span></a>
        <div class="header-right">
          <span class="version-chip">DEVELOPER PREVIEW</span><a
            href="https://github.com/Manuel1471/LiveLift"
            target="_blank"
            rel="noopener noreferrer"
          >GitHub <span aria-hidden="true">↗</span></a>
        </div>
      </header>

      <section class="hero">
        <div class="hero-copy">
          <div class="hero-kicker"><span class="kicker-line"></span> LIVEVIEW × CLIENT RUNTIME</div>
          <h1>Elixir on both sides<span class="hero-accent">.</span></h1>
          <p>
            Write your own UI and actions in Elixir. Let LiveView own the page while LiveLift runs selected interactions instantly in the browser.
          </p>
          <div class="hero-tags">
            <span>01 / Local state</span><span>02 / Server events</span><span>03 / One page</span>
          </div>
        </div>
        <div class="hero-orbit" aria-hidden="true">
          <div class="orbit-ring orbit-one"></div><div class="orbit-ring orbit-two"></div><span class="orbit-center">{}</span><span class="orbit-label orbit-client">CLIENT</span><span class="orbit-label orbit-server">SERVER</span>
        </div>
      </section>

      <section class="workspace" aria-label="Interactive LiveLift demonstration">
        <div class="workspace-intro">
          <div>
            <span class="section-index">THE PLAYGROUND / 001</span><h2>See the boundary in action</h2>
          </div><p>
            Change the local score, update the server, then sync deliberately. Both sides stay visible.
          </p>
        </div>
        <div class="panel-grid">
          <LiveLift.View.island
            id="local-counter"
            module={LiveLiftDemo.ScoreView}
            state={
              %{
                count: 10,
                step: 2,
                tone: "regular",
                title: ~s(A & B "<demo>"),
                milestone: false,
                saved_score: @saved_score,
                server_total: @server_count
              }
            }
            server_fields={[:saved_score, :server_total]}
            server_revision={@sync_revision}
          />
          <section class="server-panel" aria-label="LiveView server counter">
            <div class="panel-topline">
              <span class="eyebrow"><span class="status-dot server-dot"></span> SERVER / LIVEVIEW</span><span class="runtime-pill server-pill">WebSocket update</span>
            </div>
            <div class="panel-heading">
              <div>
                <h2>Server activity</h2><p>LiveView handles this event and patches the page.</p>
              </div><div class="mini-icon server-icon" aria-hidden="true">↗</div>
            </div>
            <div class="server-count">
              <strong id="server-count" aria-live="polite">{@server_count}</strong><span>server events</span>
            </div>
            <div class="chart-head"><span>Event history</span><strong>LAST 8</strong></div>
            <div
              class="history-chart"
              role="img"
              aria-label={"Server event history, current count #{@server_count}"}
            >
              <div :for={{value, index} <- Enum.with_index(@server_history)} class="history-bar-wrap">
                <div class="history-bar" style={"height: #{min(18 + value * 12, 100)}%"}></div><span>{index}</span>
              </div>
            </div>
            <button
              id="server-increment"
              phx-click="server_increment"
              type="button"
              class="button-server"
            >Trigger server event <span aria-hidden="true">↗</span></button>
            <div class="panel-divider"></div>
            <div class="sync-row">
              <div>
                <strong>Last synced client score</strong><span>Received via
                <code>handle_event/3</code></span>
              </div><output id="saved-score" aria-live="polite">{if @saved_score == nil,
                do: "—",
                else: @saved_score}</output>
            </div>
          </section>
        </div>
        <LiveLift.View.island
          id="task-list"
          module={LiveLiftDemo.TaskListView}
          state={
            %{
              items: @task_items,
              next_id: length(@task_items) + 1,
              draft: "",
              has_items: true,
              empty: false
            }
          }
        />
      </section>

      <section class="flow-section" aria-label="How LiveLift works">
        <div class="flow-header">
          <span class="section-index">UNDER THE HOOD / 002</span><h2>
            One page. Two execution paths.
          </h2>
        </div><div class="flow-grid">
          <div class="flow-card">
            <span>01</span><strong>Define in Elixir</strong><p>
              Your app owns the markup and <code>defclient</code> actions.
            </p>
          </div><div class="flow-card">
            <span>02</span><strong>Compile the client</strong><p>
              LiveLift builds JavaScript from its supported Elixir subset.
            </p>
          </div><div class="flow-card">
            <span>03</span><strong>Bridge when needed</strong><p>
              Send local state to LiveView with an explicit event.
            </p>
          </div>
        </div>
      </section>
      <footer class="site-footer">
        <span>LiveLift · An experiment in extending LiveView</span><span>Built with Elixir, Phoenix LiveView & JavaScript</span>
      </footer>
    </main>
    """
  end

  def handle_event("server_increment", _params, socket) do
    next_count = socket.assigns.server_count + 1
    history = Enum.take(socket.assigns.server_history ++ [next_count], -8)
    revision = socket.assigns.sync_revision + 1

    socket =
      assign(socket, server_count: next_count, server_history: history, sync_revision: revision)

    {:noreply, LiveLift.Sync.push(socket, "local-counter", revision, %{server_total: next_count})}
  end

  def handle_event("save_score", params, socket) do
    # The browser submits a proposal, not an authoritative state snapshot.
    count =
      case params do
        %{"state" => %{"count" => value}} -> value
        _ -> nil
      end

    if is_integer(count) and count >= -1_000 and count <= 1_000 and
         params["revision"] == socket.assigns.sync_revision do
      revision = socket.assigns.sync_revision + 1
      socket = assign(socket, saved_score: count, sync_revision: revision)
      {:noreply, LiveLift.Sync.push(socket, "local-counter", revision, %{saved_score: count})}
    else
      {:noreply, socket}
    end
  end
end
