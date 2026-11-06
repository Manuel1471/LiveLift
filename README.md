# LiveLift

LiveLift explores opt-in client-side interactions inside Phoenix LiveView. You
write your own HEEx and Elixir actions. LiveLift compiles the supported Elixir
expressions to JavaScript and connects them to your chosen DOM elements. It
does not ship UI components or patch LiveView or Hologram.

## Run the browser demo

The [Phoenix demo](examples/demo/README.md) contains a working LiveView with
app-owned markup, two Elixir client actions, and the generic hook. From
`examples/demo`, run
`mix setup` and `mix phx.server`, then visit <http://localhost:4000>.

## Use it in a Phoenix app

Add the local package to your app's `mix.exs`:

```elixir
{:live_lift, path: "../LiveLift"}
```

Define the actions in Elixir:

```elixir
defmodule MyApp.ScoreActions do
  use LiveLift.Client

  defclient advance(state), do: %{score: state.score + state.step, step: state.step}
  defclient retreat(state), do: %{score: state.score - state.step, step: state.step}
end
```

Generate the browser module before bundling your assets:

```sh
mix live_lift.compile MyApp.ScoreActions --output assets/js/generated_actions.js
```

Register the hook in `assets/js/app.js`:

```javascript
import {createClientHook} from "../../../../assets/js/live_lift/client_hook.js"
import {actions as scoreActions} from "./generated_actions.js"

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {LiveLift: createClientHook(scoreActions)}
})
```

That hook import path is for the included demo. In your own app, adjust it to
the location of your LiveLift checkout. If you already have hooks, merge them
into the `hooks` object. Run the compile task as part of your asset build, as
the demo's `mix.exs` does. Write your own markup in a LiveView template:

```heex
<section
  id="score"
  phx-hook="LiveLift"
  phx-update="ignore"
  data-live-lift-state={Jason.encode!(%{score: 10, step: 2})}
>
  <button type="button" data-live-lift-action="retreat">−</button>
  <output data-live-lift-text="score">10</output>
  <button type="button" data-live-lift-action="advance">+</button>
</section>
```

The island requires a unique `id`. `data-live-lift-state` is a JSON map of safe
integers. `data-live-lift-action` names a compiled action, while each
`data-live-lift-text` names a state field to display. You can choose any HTML
structure and any field or action names.

The state is browser-local after mount: it is not an assign, is not persisted,
and resets if the island remounts. The `phx-update="ignore"` boundary prevents
LiveView from replacing its children. Keep server-managed content outside it.

`defclient` currently accepts one argument, safe integer literals, `+`, `-`,
`*`, atom-keyed map literals, and map field reads. Actions must return a map of
safe integers. Unsupported syntax fails during compilation. This is a small
Elixir subset, not automatic conversion of an entire LiveView.

## Development

```sh
mix deps.get
mix test
cd assets && npm test
```

## Direction

1. Add an explicit path for sending local results to a server `handle_event/3`.
2. Expand the compiler only for forms justified by real use cases. Hologram's
   compiler is useful research, but this prototype does not depend on its
   runtime or claim general Elixir compatibility.
3. Define a synchronization contract before allowing server and browser to
   modify the same state.
