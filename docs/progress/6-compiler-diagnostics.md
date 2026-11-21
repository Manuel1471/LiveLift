# Phase 6 — Actionable compiler diagnostics

For contributors verifying the experimental migration workflow.

A rejected native opt-in must identify the source, the rejected form, a
correction or server alternative, and a stable code with a catalog entry.
Audit and compilation must report the same cause for an unsupported handler.
Valid demo actions and templates must emit the same JavaScript.

```text
client.ex:6: unsupported @client handler: unsupported client expression: System.monotonic_time() (E056)
  Use an expression from the supported client language or remove @client true to move it to a server handler. See docs/errors/E056.md
```

The [catalog](../errors/README.md) maps each native diagnostic family to an
example and a correction. Handler expression errors identify the handler
definition. Invalid socket update calls, helper declarations, delegated
renders and template nodes use their own source locations. Invalid HEEx
syntax detected by the LiveLift adapter includes the parser column. Phoenix
can intercept its own syntax errors earlier and reports those directly.

## Verification

Local on 2026-11-21 with Elixir 1.20.2, OTP 29 and Node 26.5.0 on macOS
arm64. Baseline commit `261c8e1`.

| Command | Result |
| --- | --- |
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | Passed |
| `mix test`, `LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test` | 144 tests passed in each mode, including source locations, unsupported constructs and error codes |
| `npm test` from `assets/` | 34 passed |
| `mix test` and `mix live_lift.test --cases test/live_lift_cases.json` from `examples/demo/` | 9 tests and 44 parity cases passed |
| `mix assets.build` and `mix assets.deploy` from `examples/demo/` | Passed |
| `sh test/integration/phoenix_consumer.sh` | Passed. The generator's app matches E056, the original call, the correction and the source location in audit and compilation, then builds and deploys |
| `npm ci && npm run e2e` from `bench/` | 228 tests passed in Chromium, Firefox and WebKit; 24 opt-in benchmarks skipped |
| `mix live_lift.compile --split --output assets/js/generated_views.js` in an archive of the baseline and `diff -x '*.map' -r` against the demo assets | Identical JavaScript for all 10 views and the shared runtime |

The runtime is 8,179 bytes gzip (0-byte delta) using esbuild
`--loader=js --format=esm --target=es2022 --minify` on the shared hook source
and Python `gzip.compress` at level 9 with `mtime=0`. No latency benchmark was
needed for this diagnostic change. The comparison covers the registry,
every demo chunk, and the shared runtime.

Source parsing and compile-time error messages are the surfaces exercised.
Runtime URL and key validation, client input, state authority, telemetry,
storage, and DOM sinks are outside this change. Existing negative tests
still cover unsafe URLs and names. No new input surface required a test.
