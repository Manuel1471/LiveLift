# LiveLift

LiveLift explores Hologram-like client views inside Phoenix LiveView. Your app
defines a template and actions in Elixir. LiveLift renders the initial HTML on
the server, compiles the supported template and actions to JavaScript, and
runs them in the browser. The surrounding page remains a regular LiveView.

## Run the browser demo

The [Phoenix demo](examples/demo/README.md) contains a user-defined client
view inside a regular LiveView. From `examples/demo`, run `mix setup` and
`mix phx.server`, then visit <http://localhost:4000>.

For an existing Phoenix app, follow the [integration guide](docs/phoenix-integration.md).
For the experimental two-line migration of a normal LiveComponent, see
[Opt in a LiveComponent](docs/native-livecomponent.md).

## Use it in a Phoenix app

Add the experimental Hex package to your app's `mix.exs`:

```elixir
{:live_lift, "~> 0.1.0-rc.1"}
```

Define your view in Elixir:

```elixir
defmodule MyApp.ScoreView do
  use LiveLift.Client

  client_template """
  <section>
    <h2>Score</h2>
    <button type="button" $click="retreat">−</button>
    <output class="{@tone}">{@score}</output>
    <button type="button" $click="advance">+</button>
    <p $show="milestone">Milestone reached</p>
    <button type="button" $server="save_score">Save</button>
  </section>
  """

  defclient advance(state), do: %{
    state |
    score: state.score + state.step,
    tone: if(state.score + state.step == 12, do: "milestone", else: "regular"),
    milestone: state.score + state.step == 12
  }
  defclient retreat(state), do: %{
    state |
    score: state.score - state.step,
    tone: "regular", milestone: false
  }
end
```

Run the installer once, then build assets:

```sh
mix deps.get
mix live_lift.install
mix assets.build
```

The installer wires the asset aliases and LiveSocket hook in a standard
Phoenix 1.8 app. The build generates `generated_views.js` and copies
`live_lift_runtime.js` into the app's `assets/js`. There is no import into a
LiveLift source checkout. For custom asset layouts, integrate manually as in
the [integration guide](docs/phoenix-integration.md).

The generated hook configuration in `assets/js/app.js` is equivalent to:

```javascript
import {createClientHook} from "./live_lift_runtime.js"
import {views} from "./generated_views.js"

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {LiveLift: createClientHook(views)}
})
```

The compile task discovers client views in your app and generates one registry.
Ignore the two generated JavaScript files in Git. Mount the view inside a
LiveView template:

```heex
<LiveLift.View.island
  id="score"
  module={MyApp.ScoreView}
  state={%{score: 10, step: 2, tone: "regular", milestone: false}}
/>
```

The island needs a unique `id`. Its state is local after mount and resets if
the island remounts. LiveLift creates a `phx-update="ignore"` boundary so
LiveView keeps ownership of the surrounding page. `$server="event_name"`
sends the current local state to the enclosing LiveView's `handle_event/3`.
Your handler must validate that payload before using it. The demo shows the
round trip.

For server-owned fields and versioned responses, see the [sync contract](docs/sync.md).

The current language includes text and attribute bindings, keyed lists,
conditional nodes, events with typed parameters, and presentation components
defined by the app. See the [supported client language](docs/language.md) for
exact syntax, action expressions, and validation rules. Elixir modules and
templates outside this subset are not automatically compiled for the browser.

For architecture, differences from Hologram, and limitations, see
[the comparison](docs/comparison.md).

## Development

```sh
mix deps.get
mix test
cd assets && npm test
```

This release is experimental and currently supports Phoenix LiveView 1.2.x.
See [production limits and reproducible benchmarks](docs/production-readiness.md)
before using it in a deployed app.
For bundle overhead, server event measurements and the shortest setup, see
[performance and adoption](docs/performance-and-adoption.md).
