# Experimental production limits

## Compatibility

The CI matrix runs the library tests with Phoenix LiveView 1.2.0 and 1.2.13.
Both passed locally on Elixir 1.20.2 / OTP 29 on 2026-11-06. The parser uses
`Phoenix.LiveView.TagEngine.Parser`, an internal API, so the dependency is
restricted to 1.2.x. LiveView 1.3 and later are not claimed compatible.
An optional CI lane tests LiveView `main` without blocking releases; it is an
early compatibility signal, not a supported version claim.

## Accessibility

Event directives require native controls: `$click` and `$server` on buttons,
`$input` and `$change` on form controls, and `$submit` on forms. These controls
support keyboard activation without a custom key handler. The demo labels its
inputs, exposes changing counts with `aria-live`, and retains the active input
when keyed rows move. App authors must still give controls accessible names,
test their own components with assistive technology, and avoid using color
alone to communicate state. Chromium integration tests run axe WCAG A/AA
checks on the demo. No automated screen-reader audit is claimed.

Run the real-browser suite with `cd bench && npm ci && npx playwright install
chromium && npm run e2e`. It checks client/server updates, editing and focus,
server/client DOM equivalence after a render, and the demo's axe results.
Firefox, WebKit, assistive technology and production deployment are not yet
covered.

## Source maps

`mix live_lift.compile` writes `generated_views.js.map` alongside the registry,
with the original Elixir source embedded. Each generated view entry points to
the `client_template` declaration line. Action expressions within a view entry
currently map to that declaration, so line-level action debugging is a known
limit. The demo's `assets.build` uses esbuild's external map; production builds
omit it to avoid publishing app source by default. Apps with custom bundlers
must enable source-map consumption there.

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

The [performance and adoption check](performance-and-adoption.md) measures the
bundle cost, a parent LiveView event, and keyed DOM work separately.
