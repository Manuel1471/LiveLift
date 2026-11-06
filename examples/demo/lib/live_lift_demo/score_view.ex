defmodule LiveLiftDemo.ScoreView do
  use LiveLift.Client

  client_template("""
  <section>
    <h2>Custom score</h2>
    <button type="button" $click="retreat">Subtract step</button>
    <output aria-live="polite" class="{@tone}">{@count}</output>
    <button type="button" $click="advance">Add step</button>
    <p>Step: {@step}</p>
    <p $show="milestone">Milestone reached</p>
    <button type="button" $server="save_score">Save score on server</button>
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
end
