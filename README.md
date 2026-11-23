# LiveLift

LiveLift runs selected Phoenix LiveComponent interactions in the browser. Keep
your `~H` template and `handle_event/3`; add `use LiveLift` and mark a supported
handler with `@client true`. The server still runs that handler on its own state
and sends the authoritative result. The surrounding page remains a regular
LiveView. Use `@client :local` for a preview, filter, or sort that should run
in the browser without a server event once the hook mounts.

## Run the browser demo

The [Phoenix demo](https://github.com/Manuel1471/LiveLift/blob/main/examples/demo/README.md) contains native LiveComponents and
legacy client views inside a regular LiveView. From `examples/demo`, run `mix setup` and
`mix phx.server`, then visit <http://localhost:4000>.

Use the [event telemetry guide](docs/telemetry.md) to measure frequency and
server time before opting in and compare browser latency after migration.
Use the [development inspector](docs/state-inspector.md) to compare optimistic
state and authoritative corrections in the browser. The [versioned asset guide](docs/versioned-assets.md)
covers TypeScript and the optional npm runtime.

## Use it in a Phoenix app

The experimental release has passed installation from local artifacts.
Public installation awaits publication of `0.1.0-rc.1`. See the
[verified and pending items](docs/production-readiness.md) and
[release instructions](https://github.com/Manuel1471/LiveLift/blob/main/docs/release.md).

- [Start a new Phoenix app](docs/phoenix-integration.md#start-a-new-phoenix-app)
  and build a working counter from scratch.
- [Add LiveLift to an existing app](docs/phoenix-integration.md#adopt-livelift-in-an-existing-phoenix-app)
  and opt in one handler while keeping your LiveView page.
- [Wire a custom asset pipeline](docs/phoenix-integration.md#manual-asset-integration)
  and keep your existing LiveSocket hooks.

The [native guide](docs/native-livecomponent.md) covers the supported HEEx,
the three event modes, and Elixir/JavaScript parity tests.

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
