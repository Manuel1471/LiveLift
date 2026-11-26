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
  [expiry spike](https://github.com/Manuel1471/LiveLift/blob/main/docs/offline-expiry-browser-spike.md)
  records the focused reconnect commands for deployed assets.
- **Operational controls.** Global and per-component `:live_lift` switches
  restore server-only rendering for new mounts. Active clients reload after
  their next synchronized marked event receives the disabled reply. The [security model](security.md) documents the trust
  boundary and internal XSS review.
- **Performance.** CI checks the shared hook against the 8 KiB budget.
  With the offline expiry notice it measured 8,192 bytes gzip on macOS
  and Linux. The [expiry check](https://github.com/Manuel1471/LiveLift/blob/main/docs/offline-expiry-browser-spike.md)
  covers reconnect behavior and the size measurement. The
  [runtime size check](https://github.com/Manuel1471/LiveLift/blob/main/docs/progress/7-runtime-budget.md)
  records the toolchain and reproduction command. The [native event measurements](https://github.com/Manuel1471/LiveLift/blob/main/docs/progress/6-event-telemetry.md)
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
WebKit. A weekly advisory workflow checks LiveView `main`, records the
upstream commit, and runs both parser paths. Push and pull request runs
report advisories. The weekly and manual runs surface failures in Actions.

The dependency requirement `~> 1.2.0` declares the LiveView 1.2.x range. For
deployment, use a patched release in that range and check the application's
own lockfile with `mix hex.audit`. LiveView 1.2.0 is a compatibility test
target and is affected by published security advisories. The published
subset uses a bounded fallback when the internal LiveView template parser
is unavailable. On the pinned public corpus, both paths produced identical
trees for all 158 templates that compiled in isolation. Both rejected the
remaining templates. See the
[compatibility evidence](https://github.com/Manuel1471/LiveLift/blob/main/docs/progress/7-liveview-compatibility.md).

### Browser requirements

The shared hook uses `Object.hasOwn` and `Array.prototype.at`. Operations
that count or split graphemes also use `Intl.Segmenter`, including
`String.length/1` and changeset length validation. These are the first
desktop versions with each API available.

| Browser | `Object.hasOwn` | `Array.prototype.at` | `Intl.Segmenter` |
| --- | ---: | ---: | ---: |
| Chrome | 93 | 92 | 87 |
| Firefox | 92 | 90 | 125 |
| Safari | 15.4 | 15.4 | 14.1 |

Sources are the browser compatibility data for [Object](https://github.com/mdn/browser-compat-data/blob/main/javascript/builtins/Object.json),
[Array](https://github.com/mdn/browser-compat-data/blob/main/javascript/builtins/Array.json)
and [Intl.Segmenter](https://github.com/mdn/browser-compat-data/blob/main/javascript/builtins/Intl/Segmenter.json).
The Playwright suite verifies its pinned browser versions. The table
reports API availability. End-to-end support for the historical versions
depends on the rest of the app and its asset build.

Without `Object.hasOwn`, the hook can fail during mounting. Without
`Intl.Segmenter`, grapheme-dependent marked actions raise in the browser
and can leave the event unsubmitted. A regular counter can still predict
without `Intl.Segmenter`. Keep grapheme-dependent handlers on LiveView
when serving clients without it. For broader compatibility, use the
[server-only switches](native-livecomponent.md#server-only-mode)
before mounting LiveLift. The browser suite verifies that Phoenix
validates and saves the same Unicode text with both APIs removed and
LiveLift disabled for the demo.

## Acceptance for 1.0

| Requirement | Evidence to record |
| --- | --- |
| Public API frozen for a LiveView cycle | Record the baseline LiveLift commit, the public surface being frozen, and the LiveView releases covered. |
| Zero parity differences | Run the Elixir and generated JavaScript harness on the proposed release. Record the SHA and test outcomes. |
| Two applications in production | Collect the deployment results described below for two independent apps. |
| Independent review | Record a security audit or a cross-review against the release candidate and resolve its findings. |
| Documentation for LiveView developers | Have developers install and reverse an opt-in using the published guide. Record unclear steps and their corrections. |

Phase 7 also tracks signed publication of a hosted Hex artifact,
manual assistive technology testing, and the remaining HEEx fuzzing.
The [release policy](https://github.com/Manuel1471/LiveLift/blob/main/docs/release.md)
covers versioning, deprecations, and the public verification commands.

### Pilot evidence

Record the LiveLift and LiveView versions and the component being tried.
Start from a server-only baseline. Compare interaction latency, error rates,
and event volume under comparable traffic. Exercise reconnects and roll back
to server-only mode using the published [switches](native-livecomponent.md#server-only-mode).
Record the observation window, the scope of the deployment, and any rollback
or unexpected reconciliation. Keep event parameters and state out of reports.

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
Elixir and HEEx sources. View entries and templates point to their `~H`
sigil or the start of their colocated `.html.heex` file.
Generated native actions point to their `handle_event/3` definition and to
the line of the action's outer expression when the compiler has that
location. A timer's initiating handler has a mapping. Nested expressions,
expanded helpers, and delayed callbacks have no individual segments.
The tests resolve eager and split mappings using Node's source-map API.

The demo's `assets.build` emits external bundle maps for development.
`assets.deploy` removes those maps and bundles left by the dev watcher
that embed inline maps before Phoenix builds the public manifest. The
compiler's private maps stay under `assets/js`. Custom bundlers control
which maps they consume and publish. See the
[deployment check](https://github.com/Manuel1471/LiveLift/blob/main/docs/progress/7-deployed-source-maps.md).

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
