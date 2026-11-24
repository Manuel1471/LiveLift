# Experimental production limits

## Verified

- **Native adoption.** Ordinary LiveComponents and routed LiveViews can opt in
  supported handlers. The migration diff, compiler diagnostics, audit task,
  and parity command were exercised in a generated Phoenix app. The
  [native guide](native-livecomponent.md) lists the bounded template, handler,
  timer, and form support.
- **Installation and assets.** The Mix and Igniter installers used the
  public Hex release in fresh Phoenix apps. Migration, parity, and asset build
  and deploy checks passed. Chromium, Firefox, and WebKit exercised the
  runtime shipped in Hex. The [release verification](https://github.com/Manuel1471/LiveLift/blob/main/docs/progress/6-public-registry.md)
  records the commands.
- **Browser behavior.** The suite exercises reordering, duplicates,
  reconnects, native form events, keyed focus, selected field drafts,
  and the development inspector in Chromium, Firefox, and WebKit. The
  candidate passed 246 browser tests and 12 selected tests with deployed
  assets. The 30 opt-in benchmark or spike cases were skipped in the
  default browser run.
- **Operational controls.** Global and per-component `:live_lift` switches
  restore server-only rendering for new mounts. Active clients reload after
  their next synchronized marked event receives the disabled reply. The [security model](security.md) documents the trust
  boundary and internal XSS review.
- **Performance.** The shared hook measured 8,183 bytes gzip against an
  8 KiB budget. The [native event measurements](https://github.com/Manuel1471/LiveLift/blob/main/docs/progress/6-event-telemetry.md)
  record server cost and browser latency for the measured fixture.
  The [snapshot measurement](https://github.com/Manuel1471/LiveLift/blob/main/docs/progress/unchanged-snapshot-optimization.md)
  covers browser CPU for duplicate revisions. The local-action demo checks
  that preview events produce no outbound LiveView messages after mount.

## Compatibility

CI is configured for Elixir 1.18 with OTP 27 and Elixir 1.20 with OTP 29,
using Node 22. Both stable lanes run against the repository lockfiles, which
pin Phoenix LiveView 1.2.15. The compatibility workflow covers 1.2.0 and
1.2.15 with the library tests and a fresh Phoenix app. The app verifies both
asset builds and the client/server round trip in Chromium, Firefox, and
WebKit. A separate advisory lane targets LiveView `main`.

The dependency requirement `~> 1.2.0` declares the LiveView 1.2.x range. For
deployment, use a patched release in that range and check the application's
own lockfile with `mix hex.audit`. LiveView 1.2.0 is a compatibility test
target and is affected by published security advisories. The published
subset uses a bounded fallback when the internal LiveView template parser
is unavailable. See the
[compatibility evidence](https://github.com/Manuel1471/LiveLift/blob/main/docs/progress/7-liveview-compatibility.md).

## Pending

- Verify the phase 7 security and compatibility criteria, including a
  cross-review or external audit and the full HEEx fuzzing work.
- Complete client error reporting and the release and deprecation policy.
- Collect evidence from two real applications in production and at least one
  LiveView cycle with a frozen API before declaring 1.0.

The [roadmap](https://github.com/Manuel1471/LiveLift/blob/main/ROADMAP.md) tracks the gates in order.

## Accessibility

Use native buttons for `phx-click` and native form controls for changes and
submissions. These controls support keyboard activation. The demo labels its
inputs, exposes changing counts with `aria-live`, and retains the active input
when keyed rows move. App authors must still give controls accessible names,
test their own components with assistive technology, and avoid using color
alone to communicate state. Chromium, Firefox and WebKit integration tests
verify focus retention and run axe WCAG A/AA checks on the demo. No automated
screen-reader audit is claimed.

Run the real-browser suite with `cd bench && npm ci && npx playwright install
chromium firefox webkit && npm run e2e`. It checks client/server updates, editing and focus,
server/client DOM equivalence after a render, and the demo's axe results.
The suite also mounts 100 opted-in components on one page and verifies that
their events and state remain independent in all three browsers. Assistive
technology and production deployment are not yet covered.

## Source maps

`mix live_lift.compile` writes a registry source map in eager mode. Split
mode writes a map for each generated view module. Both embed the original
Elixir source and map each generated view entry to its `~H` sigil. The consumer test resolves the
split native mapping through Node's source-map API. Mapping individual
action expressions remains pending.

The demo's `assets.build` emits external bundle maps. Use a clean workspace
for `assets.deploy`. A previous `assets.build` can leave maps in the static
output directory, and Phoenix can digest those files on the next deploy. Custom bundlers
must explicitly configure consumption of the generated maps.

## Benchmarks

Run `mix run bench/benchmark.exs` from the repository root. It measures 100
server renders each for keyed lists of 10, 100 and 1,000 elements, plus 10,000
invocations of the same increment action in Elixir and generated JavaScript.
The code warms each path once and reports median and p95 microseconds. Results
from an Apple M4 Mac, Elixir 1.20.2 / OTP 29 / Node 26.5.0 on 2026-11-06:

| Operation | Median | p95 |
| --- | ---: | ---: |
| Initial server render, 10 rows | 8.54 µs | 10.83 µs |
| Initial server render, 100 rows | 89.63 µs | 128.25 µs |
| Initial server render, 1,000 rows | 902.71 µs | 1,025.54 µs |
| Increment action, Elixir | 0.041 µs | 0.042 µs |
| Increment action, JavaScript | 0.125 µs | 0.167 µs |

These are local compute measurements. They do not include DOM reconciliation,
network latency, memory, concurrent users, or LiveView diff transport; the
Elixir and JavaScript timers have different overhead. They cannot establish
that one architecture is faster in a real application. Use LiveLift for small,
pure interactions that benefit from immediate client response while LiveView
continues to own server workflows. Benchmark the complete app before making a
production performance claim.

The [performance and adoption check](https://github.com/Manuel1471/LiveLift/blob/main/docs/performance-and-adoption.md) measures the
bundle cost, a parent LiveView event, and keyed DOM work separately.
