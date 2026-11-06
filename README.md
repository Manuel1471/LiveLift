# LiveLift

LiveLift explores Hologram-like client views inside Phoenix LiveView. Your app
defines a template and actions in Elixir. LiveLift renders the initial HTML on
the server, compiles the supported template and actions to JavaScript, and
runs them in the browser. The surrounding page remains a regular LiveView.

## Run the browser demo

The [Phoenix demo](examples/demo/README.md) contains a user-defined client
view inside a regular LiveView. From `examples/demo`, run `mix setup` and
`mix phx.server`, then visit <http://localhost:4000>.

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
    <output>{@score}</output>
    <button type="button" $click="advance">+</button>
  </section>
  """

  defclient advance(state), do: %{score: state.score + state.step, step: state.step}
  defclient retreat(state), do: %{score: state.score - state.step, step: state.step}
end
```

Generate the browser module before bundling your assets:

```sh
mix live_lift.compile --output assets/js/generated_views.js
```

Register the hook in `assets/js/app.js`:

```javascript
import {createClientHook} from "../../../../assets/js/live_lift/client_hook.js"
import {views} from "./generated_views.js"

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {LiveLift: createClientHook(views)}
})
```

The compile task discovers client views in your app and generates one registry.
The hook import path shown is for the included demo. In your own app, adjust it
to the location of your LiveLift checkout. If you already have hooks, merge
them into the `hooks` object. Run the compile task as part of your asset build,
as the demo's `mix.exs` does. Mount the view inside a LiveView template:

```heex
<LiveLift.View.island
  id="score"
  module={MyApp.ScoreView}
  state={%{score: 10, step: 2}}
/>
```

The island needs a unique `id`. Its state is local after mount: it is not a
LiveView assign, is not persisted, and resets if the island remounts. LiveLift
creates a `phx-update="ignore"` boundary so LiveView keeps ownership of the
surrounding page.

The current template syntax supports text interpolation (`{@field}`) and
`$click="action"`; it does not yet support dynamic attributes, components,
control flow, or general Elixir expressions. `defclient` supports one argument,
safe integer literals, `+`, `-`, `*`, atom-keyed map literals, and map field
reads. State and action results must be maps of safe integers. Unsupported
syntax fails during compilation.

## Development

```sh
mix deps.get
mix test
cd assets && npm test
```

## Direction

1. Add dynamic attributes, conditional and repeated markup, and more Elixir
   expressions to the compiler.
2. Add an explicit path for sending local results to `handle_event/3`.
3. Define a synchronization contract before allowing server and browser to
   modify the same state. Hologram's compiler and runtime are useful research,
   but LiveLift does not currently depend on them or claim general Elixir
   compatibility.
