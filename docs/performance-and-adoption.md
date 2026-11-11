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
After no-change render skipping, the same bundle script measured 169,744 raw
and 51,819 gzip with LiveLift, or +4,598 gzip over Phoenix alone. The skip
adds about 98 gzip bytes in this build.
With keyed-row reuse, the script measured 171,111 raw and 52,229 gzip bytes
for the LiveLift app: +5,008 gzip over Phoenix. The runtime size budget remains
open.
After the native attributes and bounded offline queue, the same script measured
172,584 raw and 52,698 gzip bytes: +5,477 gzip over the Phoenix baseline.
A November 2026 run after flat native form changes measured 174,045 raw and
53,093 gzip bytes with LiveLift, versus 152,732 raw and 47,221 gzip for the
Phoenix baseline: +5,872 gzip. This measures an example app and build, not a
fixed cost for every LiveView page.

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
The latest run measured 42 µs for Phoenix and 56 µs with one island (median
of five runs). The ~14 µs difference is local measurement noise and work for
this small server event, not a general Phoenix overhead estimate.
A later isolated run measured 42 µs for Phoenix and 55 µs with one island
(median of five runs). The 13 µs difference is a local measurement for this
small handler; it is not a universal server cost.

Run `cd examples/demo && mix assets.build`, then `cd ../../bench && npm ci &&
npm run dom` for a DOM-model benchmark of reversing the demo's keyed list.
With Node 26.5.0 and linkedom, median times were about 0.38 ms for 10 rows,
3.87 ms for 100 rows, and 72.86 ms for 1,000 rows. A repeat measured 77.02 ms
for 1,000 rows. Linkedom is not a browser,
so these are a regression signal for LiveLift's DOM work, not a browser
latency claim. Large changing lists remain an important limit. Prefer LiveView
streams for large server-owned collections.
The runtime now skips DOM reconciliation when an action or server reply leaves
the validated state structurally unchanged. In a 50-sample linkedom run with
1,000 rows, a no-change action took 0.52 ms median, while reversing the same
list took 79.51 ms. Both still validate state; the no-change path avoids
building and patching 1,000 DOM rows. These are local DOM-model timings.

For keyed loops whose row content depends only on the immutable item, the
runtime now reuses the existing row when the same item moves. A subsequent
50-sample linkedom run measured 52.32 ms median for reversing 1,000 rows.
The browser benchmark (`cd bench && LIVE_LIFT_BENCH=1 npx playwright test -g
"1,000 keyed row"`) measured 3.3 ms median and 7.5 ms p95 across 25
Chromium reversals on the same machine. It checks row count, order, input
identity and value. This is one app and machine, not a guarantee that every
1,000-row view fits in a frame. Rows reading parent state still render when
that state changes.

The native list demo accepts `/native-list?rows=1000`. Run
`cd bench && LIVE_LIFT_BENCH=1 npx playwright test --project=chromium -g
"1,000 native"` for 25 client-side reversals while disconnected, without
server reply timing mixed in. A local Chromium run measured 10.5 ms median
and 15.8 ms p95; the same run preserved all 1,000 rows and the input node
inside a moved row. The legacy list benchmark on that machine measured
3.2 ms median and 7.4 ms p95. The native row has a form and a remove button,
so these are different DOM workloads. The native p95 is close to a 16.7 ms
frame budget; measure your own component before moving a large list.

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

The demo route `/many-islands?count=100` mounts 100 independent opted-in
components; `mode=server` uses the same component in server mode. Run
`cd bench && LIVE_LIFT_BENCH=1 npm run e2e -- --project=chromium --grep
"benchmark navigation and mount"` to compare them. Seven samples after two
warmups on the same machine gave 37.9 ms median / 39.1 ms p95 for server mode
and 41.4 ms median / 53.2 ms p95 for client mode. This includes navigation,
server render, LiveView connection and browser mount; it is a small local
sample, not an isolated hook cost or a production latency promise. The regular
browser suite verifies that first, middle and last islands update without
changing neighboring islands in Chromium, Firefox and WebKit.

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
