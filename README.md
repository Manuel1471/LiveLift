# LiveLift

LiveLift explores opt-in client-side interactions inside Phoenix LiveView. Its
first prototype compiles simple Elixir actions into JavaScript so a counter
responds to clicks without a server round trip. It is a separate library; it
does not patch LiveView or Hologram.

## Run the browser demo

The [Phoenix demo](examples/demo/README.md) contains a working LiveView, two
Elixir client actions, and the JavaScript hook. From `examples/demo`, run
`mix setup` and `mix phx.server`, then visit <http://localhost:4000>.

## Use it in a Phoenix app

Add the local package to your app's `mix.exs`:

```elixir
{:live_lift, path: "../LiveLift"}
```

Define the actions in Elixir:

```elixir
defmodule MyApp.CounterActions do
  use LiveLift.Client

  defclient increment(count), do: count + 1
  defclient decrement(count), do: count - 1
end
```

Generate the browser module before bundling your assets:

```sh
mix live_lift.compile MyApp.CounterActions --output assets/js/generated_actions.js
```

Register the hook in `assets/js/app.js`:

```javascript
import {createCounterHook} from "../../../../assets/js/live_lift/counter.js"
import {actions as counterActions} from "./generated_actions.js"

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {"LiveLift.Counter": createCounterHook(counterActions)}
})
```

That hook import path is for the included demo. In your own app, adjust it to
the location of your LiveLift checkout. If you already have hooks, merge them
into the `hooks` object. Run the compile task as part of your asset build, as
the demo's `mix.exs` does. Then use the component in a LiveView template:

```heex
<LiveLift.Counter.counter id="demo-counter" initial={10} />
```

The component requires a unique `id`. Its count is browser-local after mount;
it is not an assign, is not persisted, and resets if the component remounts.
The `phx-update="ignore"` boundary keeps LiveView's DOM patches from replacing
the counter's children. Do not put server-managed content inside that boundary.

`defclient` currently accepts one integer argument, integer literals, and
`+`, `-`, `*`. Unsupported syntax fails during compilation. JavaScript numbers
are limited to safe integers; the hook rejects results outside that range.

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
