# LiveLift

LiveLift runs selected interactions from Phoenix LiveView and LiveComponents in the browser. Keep
your `~H` template and `handle_event/3`; add `use LiveLift` and mark a supported
handler with `@client true`. The server still runs that handler on its own state
and sends the authoritative result. The surrounding page remains a regular
LiveView. Use `@client :local` for a preview, filter, or sort that should run
in the browser without a server event once the hook mounts.

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

## Learn the event model

- [How state and events move](docs/sync.md) follows an optimistic click
  from the first browser update through server confirmation.
- [Adoption practices](docs/best-practices.md) help you choose an event mode,
  keep state small, test both runtimes, and measure the result.
- [Supported Elixir and HEEx](docs/language.md) describes what the browser
  compiler accepts.
- [Development inspector](docs/state-inspector.md) helps you see predictions
  and corrections. [Versioned assets](docs/versioned-assets.md) covers
  TypeScript and the optional npm runtime.

## Run the browser demo

From `examples/demo`, run `mix setup` and `mix phx.server`. Open
<http://localhost:4000/local-actions> to compare a sort that stays in the
browser, a shared counter confirmed by LiveView, and a selection saved by
a server handler. See the [demo guide](https://github.com/Manuel1471/LiveLift/blob/main/examples/demo/README.md).

## Development

```sh
mix deps.get
npm ci --prefix bench
mix test
cd assets && npm test
```

This release is experimental and currently supports Phoenix LiveView 1.2.x.
See [production limits and reproducible benchmarks](docs/production-readiness.md)
before using it in a deployed app.
See the [security model](docs/security.md) before sending client values to a
server handler or including app state in an island.
