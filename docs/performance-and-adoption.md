# Performance and adoption check

LiveLift is opt-in. A normal LiveView without an island keeps its regular
server event path. An island uses a standard LiveView hook and
`phx-update="ignore"`; LiveView still renders the island component on parent
updates, so the server cost is not zero.

## Measurements

Run `bench/phoenix_bundle.sh` to generate two fresh Phoenix apps from the same
template, add one tiny LiveLift view to the second, and compare minified bundles.
On an Apple M4 Mac with Elixir 1.20.2 / OTP 29 on 2026-11-06:

| Production JavaScript | Phoenix | Phoenix + one LiveLift view | Difference |
| --- | ---: | ---: | ---: |
| Raw | 152,732 bytes | 162,251 bytes | +9,519 bytes |
| Gzip | 47,221 bytes | 50,037 bytes | +2,816 bytes (6.0%) |

Run `bench/phoenix_event.sh` for two generated apps with the same `add`
LiveView handler. Five runs of 200 `Phoenix.LiveViewTest.render_click/1` calls
(after 20 warmups) gave median per-event times of 41 µs without an island and
54 µs with one tiny island. That is about 13 µs extra in this local test. It
does not measure network,
browser rendering, concurrent users or a deployed BEAM. The app's island and
server event workload affect the result; do not extrapolate a universal
percentage from it.

Run `cd examples/demo && mix assets.build`, then `cd ../../bench && npm ci &&
npm run dom` for a DOM-model benchmark of reversing the demo's keyed list.
With Node 26.5.0 and linkedom, median times were about 0.35 ms for 10 rows,
3.28 ms for 100 rows, and 71.7 ms for 1,000 rows. Linkedom is not a browser,
so these are a regression signal for LiveLift's DOM work, not a browser
latency claim. Every action currently rebuilds a desired subtree; large
lists are an important limit. Prefer LiveView streams for large collections.

The gain is interaction latency when a small pure action can finish locally
without a server round trip. A server-backed action still needs LiveView.
LiveLift does not make Phoenix generally faster, and it adds bundle and render
costs to pages where an island is mounted.

## Learning and integration

A standard Phoenix 1.8 app adds one dependency and runs `mix live_lift.install`.
The installer updates `assets/js/app.js`, the two asset aliases in `mix.exs`,
and `.gitignore`; it is idempotent. App code then needs three concepts:
`client_template`, `defclient`, and `<LiveLift.View.island>`. A simple counter
can use ordinary Elixir map update syntax:

```elixir
defmodule MyApp.CounterClient do
  use LiveLift.Client
  client_template "<button type=\"button\" $click=\"add\">Add</button><output>{@count}</output>"
  defclient add(state), do: %{state | count: state.count + 1}
end
```

```heex
<LiveLift.View.island id="counter" module={MyApp.CounterClient} state={%{count: 0}} />
```

The developer must already know basic Phoenix LiveView and Elixir maps. Lists,
components and server synchronization add more concepts; see the language and
sync guides. The installer recognizes standard Phoenix 1.8 asset files. A
custom LiveSocket or asset pipeline still needs manual integration.

## Code quality limits

The compiler rejects unsupported expressions and parity tests compare the
published subset with generated JavaScript. The demo and a second generated
Phoenix app pass their integration tests. The main risks before a stable
release are the internal LiveView parser dependency, incomplete Elixir
semantics, coarse source maps for actions, and full-subtree work on every
client update. These limits matter more than the small action microbenchmark.
