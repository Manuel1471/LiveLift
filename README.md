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

## Use it in a Phoenix app

Add the local package to your app's `mix.exs`:

```elixir
{:live_lift, path: "../LiveLift"}
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
    score: state.score + state.step,
    step: state.step,
    tone: if(state.score + state.step == 12, do: "milestone", else: "regular"),
    milestone: state.score + state.step == 12
  }
  defclient retreat(state), do: %{
    score: state.score - state.step, step: state.step,
    tone: "regular", milestone: false
  }
end
```

Generate the browser module before bundling your assets:

```sh
mix live_lift.compile --output assets/js/generated_views.js
```

This also copies `live_lift_runtime.js` beside the generated registry. Both
files are local to your app's assets; the build does not need a relative import
into the dependency's source tree. You can choose another runtime path with
`--runtime-output`.

Register the hook in `assets/js/app.js`:

```javascript
import {createClientHook} from "./live_lift_runtime.js"
import {views} from "./generated_views.js"

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {LiveLift: createClientHook(views)}
})
```

The compile task discovers client views in your app and generates one registry.
If you already have hooks, merge them into the `hooks` object. Run the compile
task as part of your asset build, as the demo's `mix.exs` does. Ignore the two
generated JavaScript files in Git. Mount the view inside a LiveView template:

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

The current template syntax supports text interpolation (`{@field}`), dynamic
`class`, `title`, `aria-label`, and `value` attributes (`class="{@field}"`), conditional
visibility (`$show="field"`), client actions (`$click="action"`), and explicit
server events (`$server="event"`). `defclient` supports one argument, safe
integer, string, boolean, and nil literals, `+`, `-`, `*`, `==`, `!=`, `if` with
both branches, atom-keyed map literals, and map field reads. State and action
results must be flat maps with atom keys and safe integer, string, boolean, or
nil values. Unsupported syntax fails during compilation. Elixir modules and
templates outside this subset are not automatically compiled for the browser.

For architecture, differences from Hologram, and limitations, see
[the comparison](docs/comparison.md).

## Development

```sh
mix deps.get
mix test
cd assets && npm test
```

## Direction

1. Add repeated markup, nested state, forms, and more Elixir expressions.
2. Define a synchronization contract before allowing server and browser to
   modify the same state.
3. Add source maps and stronger compiler validation for larger client views.
