defmodule LiveLiftDemo.ScoreView do
  use LiveLift.Client

  client_template("""
  <section>
    <h2>Custom score</h2>
    <button type="button" $click="retreat">Subtract step</button>
    <output aria-live="polite">{@count}</output>
    <button type="button" $click="advance">Add step</button>
    <p>Step: {@step}</p>
  </section>
  """)

  defclient(advance(state), do: %{count: state.count + state.step, step: state.step})
  defclient(retreat(state), do: %{count: state.count - state.step, step: state.step})
end
