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
| Raw | 152,732 bytes | 163,785 bytes | +11,053 bytes |
| Gzip | 47,221 bytes | 50,478 bytes | +3,257 bytes (6.9%) |

A repeat after the state and event limit checks measured 152,732 bytes raw
and 47,221 bytes gzip for Phoenix, versus 169,367 bytes raw and 51,721 bytes
gzip with LiveLift: +16,635 raw and +4,500 gzip (9.5%). The runtime budget
therefore needs attention before v0.6.

Run `bench/phoenix_event.sh` for two generated apps with the same `add`
LiveView handler. Five runs of 200 `Phoenix.LiveViewTest.render_click/1` calls
(after 20 warmups) gave median per-event times of 49 µs without an island and
60 µs with one tiny island. That is about 11 µs extra in this local test. It
does not measure network,
browser rendering, concurrent users or a deployed BEAM. The app's island and
server event workload affect the result; do not extrapolate a universal
percentage from it.

The same script repeated after the limit checks gave a median of 46 µs for
Phoenix and 56 µs with one island across five runs, about 10 µs extra in
this local workload.

Run `cd examples/demo && mix assets.build`, then `cd ../../bench && npm ci &&
npm run dom` for a DOM-model benchmark of reversing the demo's keyed list.
With Node 26.5.0 and linkedom, median times were about 0.38 ms for 10 rows,
3.87 ms for 100 rows, and 72.86 ms for 1,000 rows. A repeat measured 77.02 ms
for 1,000 rows. Linkedom is not a browser,
so these are a regression signal for LiveLift's DOM work, not a browser
latency claim. Every action currently rebuilds a desired subtree; large
lists are an important limit. Prefer LiveView streams for large collections.

The gain is interaction latency when a small pure action can finish locally
without a server round trip. A server-backed action still needs LiveView.
LiveLift does not make Phoenix generally faster, and it adds bundle and render
costs to pages where an island is mounted.

The native LiveComponent path also has a Chromium benchmark:
`cd bench && LIVE_LIFT_BENCH=1 npx playwright test -g "benchmark native"`.
It compares the same counter handler with and without the two-line opt-in,
injecting 150 ms of LiveSocket latency. On the same machine, 20 samples after
three warmups gave median Playwright-observed times of 17.5 ms to show the
client prediction, 806.3 ms to receive its server confirmation, and 813.6 ms
to show the server-only result. A repeat on 2026-11-06 measured 17 ms, 812.1 ms,
and 813.8 ms respectively. The local figure includes Playwright command
overhead; these numbers demonstrate the round-trip avoided for immediate
feedback, not a universal production latency claim.

## Learning and integration

A standard Phoenix 1.8 app adds one dependency and runs `mix live_lift.install`.
The installer updates `assets/js/app.js`, the two asset aliases in `mix.exs`,
and `.gitignore`; it is idempotent. For the supported native LiveComponent
subset, app code adds `use LiveLift` and marks a handler with `@client true`:

```elixir
defmodule MyAppWeb.Counter do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns), do: ~H"<button phx-click=\"inc\" phx-target={@myself}>{@count}</button>"

  @client true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end
end
```

Handlers without the marker continue on the server. The browser supports a
documented subset of `~H`, event params, and handler expressions; unsupported
forms fail compilation with a source location. The older `client_template`,
`defclient`, and `<LiveLift.View.island>` API still works for existing apps.
See the [native component guide](native-livecomponent.md) for exact limits.
The installer recognizes standard Phoenix 1.8 asset files. A custom
LiveSocket or asset pipeline still needs manual integration.

## Code quality limits

The compiler rejects unsupported expressions and parity tests compare the
published subset with generated JavaScript. The demo and a second generated
Phoenix app pass their integration tests. The main risks before a stable
release are the internal LiveView parser dependency, incomplete Elixir
semantics, coarse source maps for actions, and full-subtree work on every
client update. These limits matter more than the small action microbenchmark.
