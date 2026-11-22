# Regression test maintenance

This update exercises existing behavior on the experimental release.
It keeps the phase 6 publication gate and the production criteria in the
roadmap.

## Coverage

- The reconnect test drops the first marked event on the WebSocket,
  observes the new instance and verifies that the next increment is the
  only one acknowledged by that instance.
- The form tests advance the browser clock to 299 ms and 300 ms, verify
  blur behavior, and use a second acknowledged submit as a barrier to
  check that canceled validation never reached LiveView. CI also runs
  these cases against the digested bundle.
- The installer tests check that generated TypeScript declarations are
  ignored exactly once and the ignore file survives a rejected install.
- The local npm consumer resolves a split JavaScript view's actual
  mapping back to the native `~H` line in the source file. It checks the
  referenced map and embedded Elixir source.

## Verification

Local on 2026-11-22 with Elixir 1.20.2, OTP 29, Node 26.5.0 and the
Phoenix generator 1.8.16 on macOS arm64. Test commit `18de496`.

| Command | Result |
| --- | --- |
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | Passed |
| `mix test` and `LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test` | 146 passed per parser on the locked LiveView 1.2.13 |
| `LIVE_LIFT_LIVE_VIEW_VERSION='== 1.2.0' mix deps.update phoenix_live_view`, `mix deps.get`, and the same two suites in a disposable checkout with its bench dependencies installed | Confirmed LiveView 1.2.0 at runtime. 146 passed per parser |
| `npm test` from `assets/` | 34 passed |
| `mix test`, `mix live_lift.test --cases test/live_lift_cases.json`, `mix assets.build`, `mix assets.deploy` from `examples/demo/` | 9 tests and 44 parity cases passed. Both asset commands passed |
| `sh test/integration/phoenix_consumer.sh` and `LIVE_LIFT_INTEGRATION_IGNITER=1 sh test/integration/phoenix_consumer.sh` | Both passed, including the split source-map, strict TypeScript and mismatched-runtime checks in the npm consumer |
| `npm ci && npm run e2e` from `bench/` | 243 passed across Chromium, Firefox and WebKit. 24 opt-in benchmarks skipped |
| `LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/island_loading.spec.mjs e2e/devtools.spec.mjs` and the focused reconnect and debounce check | 12 existing digested cases plus all 9 refreshed cases passed |

The TypeScript consumer ran against the actual local tarball. The changes
are in tests, CI, and documentation, so the shared browser hook and
compiler are unchanged. No runtime benchmark was rerun.


The public checks still returned no Hex release and npm HTTP 404 for
`0.1.0-rc.1`. Public installation, hosted CI, and the later roadmap gates
remain pending.
