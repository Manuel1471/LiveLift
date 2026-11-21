# Phase 6 — Development state inspector

For contributors verifying the experimental inspector.

Acceptance covers recording the initial state, a prediction and a distinct
server correction, moving backward and forward while LiveView continues to
confirm events, safe rendering of state values, and removing history on
unmount. The inspector must remain opt-in during development and be removed
from deployed assets. It must fit without growing the shared runtime.

The [spike](../devtools-state-spike.md) confirmed that the hook's state
assignments can be observed outside the shared runtime. The build fixture
also found that an undefined esbuild flag can leave the inspector module in
minified assets. The [decision](../decisions/ADR-0006-development-state-history.md)
uses an explicit false build definition and puts history in a separate
dialog. The [usage guide](../state-inspector.md) shows the app integration.

## Verification

Local on 2026-11-21, macOS arm64, Elixir 1.20.2, OTP 29, Node 26.5.0 and
esbuild 0.25.4. Production bundle comparison baseline `55c9dec`.

| Command | Result |
| --- | --- |
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | Passed |
| `mix test`, `LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test` | 144 passed in each mode |
| `npm test` from `assets/` | 34 passed |
| `mix test` and `mix live_lift.test --cases test/live_lift_cases.json` from `examples/demo/` | 9 tests and 44 parity cases passed |
| `mix assets.build`, `mix assets.deploy` from `examples/demo/` | Passed |
| `sh test/integration/phoenix_consumer.sh` | Passed the existing installer, native migration, audit, tests, and assets checks |
| `mix hex.build --output <local tarball>` | The package contains the opt-in module and its guide. The guide's exact snippet resolves against the unpacked package in a generated Phoenix app and was bundled with both esbuild definitions |
| `npm ci && npm run e2e` from `bench/` | 243 passed across Chromium, Firefox and WebKit; 24 opt-in benchmarks skipped |
| `npm run e2e -- devtools.spec.mjs` from `bench/` | 15 passed after consolidating the development watcher configuration |
| `LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/island_loading.spec.mjs e2e/devtools.spec.mjs` from `bench/` | 12 passed with digested assets; 12 development-only cases skipped |
| `mix assets.deploy` for two clean checkout archives, followed by `diff -qr` on deployed JS directories | Byte-identical files, including the entry and island chunks |

The deployed demo entry is 180,514 bytes (55,026 gzip using Python
`gzip.compress` at level 9 with `mtime=0`) in both builds. The shared runtime
source is byte-identical and remains 8,179 bytes gzip with the documented
runtime method. No latency benchmark was rerun for the deployed path, whose
artifacts are identical.

The inspector only consumes the already-visible hook state. The query is
an exact shallow toggle and is inactive in deployed assets. State is written
as DOM text. No network event, persistence, telemetry field, state mutation,
HTML evaluation, or URL sink was added. Browser tests exercise input looking
like markup, frame limits, and continued server authority while inspecting.
The workflow was checked locally and its hosted run is pending.
