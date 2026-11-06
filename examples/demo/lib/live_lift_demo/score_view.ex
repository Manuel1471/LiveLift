defmodule LiveLiftDemo.ScoreView do
  use LiveLift.Client

  client_template("""
  <section class="client-panel" aria-label="Client-side score">
    <div class="panel-topline">
      <span class="eyebrow"><span class="status-dot"></span> CLIENT / ELIXIR</span>
      <span class="runtime-pill">Instant interaction</span>
    </div>
    <div class="panel-heading">
      <div>
        <h2>Local score</h2>
        <p>Actions compiled from <code>defclient</code> run in your browser.</p>
      </div>
      <div class="mini-icon" aria-hidden="true">↗</div>
    </div>
    <div class="score-row">
      <output aria-live="polite" class="{@tone}">{@count}</output>
      <div class="score-meta"><span>points</span><span>+{@step} per click</span></div>
    </div>
    <div class="chart-head"><span>Progress to 20</span><strong>{@count} / 20</strong></div>
    <progress value="{@count}" max="20" aria-label="Local score progress"></progress>
    <div class="chart-scale"><span>0</span><span>5</span><span>10</span><span>15</span><span>20</span></div>
    <p class="milestone-note" $show="milestone">✦ Milestone reached at 12</p>
    <div class="client-actions">
      <button type="button" class="button-quiet" $click="retreat" aria-label="Subtract two points">− 2</button>
      <button type="button" class="button-primary" $click="advance" aria-label="Add two points">+ 2 points <span aria-hidden="true">↗</span></button>
      <button type="button" class="button-quiet" $click="reset">Reset</button>
    </div>
    <div class="panel-divider"></div>
    <div class="sync-row">
      <div><strong>Send this value to LiveView</strong><span>Explicit bridge through <code>handle_event/3</code></span></div>
      <button type="button" class="button-sync" $server="save_score">Sync score <span aria-hidden="true">→</span></button>
    </div>
  </section>
  """)

  defclient(advance(state),
    do: %{
      count: state.count + state.step,
      step: state.step,
      tone: if(state.count + state.step == 12, do: "milestone", else: "regular"),
      milestone: state.count + state.step == 12
    }
  )

  defclient(retreat(state),
    do: %{count: state.count - state.step, step: state.step, tone: "regular", milestone: false}
  )

  defclient(reset(state),
    do: %{count: 10, step: state.step, tone: "regular", milestone: false}
  )
end
