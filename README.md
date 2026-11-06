# LiveLift

LiveLift explores opt-in client-side interactions inside Phoenix LiveView. This
initial prototype provides a counter that responds to clicks without a server
round trip. It is a separate library; it does not patch LiveView or Hologram.

## Try it in a Phoenix app

Add the local package to your app's `mix.exs`:

```elixir
{:live_lift, path: "../LiveLift"}
```

Register the hook in `assets/js/app.js`:

```javascript
import {hooks as liveLiftHooks} from "../../deps/live_lift/assets/js/live_lift/counter.js"

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...liveLiftHooks}
})
```

If you already have hooks, merge them into the `hooks` object. Then use the
component in a LiveView template:

```heex
<LiveLift.Counter.counter id="demo-counter" initial={10} />
```

The component requires a unique `id`. Its count is browser-local after mount;
it is not an assign, is not persisted, and resets if the component remounts.
The `phx-update="ignore"` boundary keeps LiveView's DOM patches from replacing
the counter's children. Do not put server-managed content inside that boundary.

## Development

```sh
mix deps.get
mix test
cd assets && npm test
```

## Direction

1. Prove that a local component can coexist with LiveView updates and lifecycle.
2. Add an explicit path for sending local results to a server `handle_event/3`.
3. Explore compiling a restricted, pure Elixir action for the browser. Hologram's
   compiler is useful research, but this prototype does not depend on its
   runtime or claim general Elixir compatibility.
4. Define a synchronization contract before allowing server and browser to
   modify the same state.

This first commit intentionally tests the browser-owned state boundary, not
Elixir-to-JavaScript compilation.
