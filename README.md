# LiveLift

LiveLift runs selected Phoenix LiveComponent interactions in the browser. Keep
your `~H` template and `handle_event/3`; add `use LiveLift` and mark a supported
handler with `@client true`. The server still runs that handler on its own state
and sends the authoritative result. The surrounding page remains a regular
LiveView.

## Run the browser demo

The [Phoenix demo](examples/demo/README.md) contains native LiveComponents and
legacy client views inside a regular LiveView. From `examples/demo`, run `mix setup` and
`mix phx.server`, then visit <http://localhost:4000>.

For an existing Phoenix app, follow the [integration guide](docs/phoenix-integration.md).
See the [migration diff](docs/liveview-migration-diff.md) for an existing
LiveComponent and the [native guide](docs/native-livecomponent.md) for
supported handlers.
Run `mix live_lift.audit` to see which existing LiveView and LiveComponent handlers fit the
current client subset and why others are blocked.
Run `mix live_lift.test --cases test/live_lift_cases.json` in your app's CI to
compare every marked handler in Elixir and Node; see the
[native component guide](docs/native-livecomponent.md).
Use the [event telemetry guide](docs/telemetry.md) to measure frequency and
server time before opting in and compare browser latency after migration.
Use the [development inspector](docs/state-inspector.md) to compare optimistic
state and authoritative corrections in the browser.

## Use it in a Phoenix app

Add the experimental Hex package to your app's `mix.exs`:

```elixir
{:live_lift, "~> 0.1.0-rc.1"}
```

Use an ordinary stateful LiveComponent and mark a compatible handler:

```elixir
defmodule MyAppWeb.Counter do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns) do
    ~H"""
    <button phx-click="inc" phx-target={@myself}>{@count}</button>
    """
  end

  @client true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end
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

The compile task discovers opted-in components in your app and generates one
registry. Ignore the generated JavaScript files in Git. Mount the component in
a LiveView template:

```heex
<.live_component module={MyAppWeb.Counter} id="counter" count={10} />
```

LiveLift creates the `phx-update="ignore"` boundary for the opted-in component.
Marked events predict locally, travel through the normal LiveView channel, and
converge on the server result. Unmarked events stay on the server. The
[native component guide](docs/native-livecomponent.md) describes the current
language subset and compile-time failures. Use `mix live_lift.audit` before
opting in a larger component.

For server-owned fields and versioned responses, see the [sync contract](docs/sync.md).

The older `LiveLift.Client`, `client_template`, `defclient`, `$click`, and
`LiveLift.View.island` API still runs for existing apps and now emits migration
warnings. Its syntax and limits remain in the [integration guide](docs/phoenix-integration.md).
Elixir modules and templates outside the supported subset are not automatically
compiled for the browser.

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
See the [security model](docs/security.md) before sending client values to a
server handler or including app state in an island.
