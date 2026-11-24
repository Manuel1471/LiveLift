# Phase 7 — Browser error reporting

The browser test first confirmed that a rejected view import only wrote
to the console. The native error listener observed no report. The hook
now uses the standard browser error channel, with console output when
`reportError` is unavailable. The standard event carries a fixed message
and omits the caught error. Offline replay still restores the server
snapshot and drops the failed queue, with a fixed diagnostic.

## Verification

On 2026-11-24, on macOS 26.5.2 (arm64), Elixir 1.20.2, OTP 29, Node
26.5.0 and Playwright 1.65.0:

| Command | Result |
| --- | --- |
| `cd bench && LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/island_loading.spec.mjs e2e/event_telemetry.spec.mjs` | 18 passed across Chromium 158.0.8127.18, Firefox 159.0, and WebKit 27.2. The probe confirmed one report, redaction of a synthetic exception, console fallback, and LiveView continuity using deployed assets. |
| `cd assets && npm test` | 34 passed. Offline replay restores the authoritative state, clears the queue and emits the fixed error. |
| `mix test test/live_lift/component_test.exs` | 31 passed. The server wrapper reports duration and outcome without event parameter values. |
| `mix format --check-formatted && mix test && mix docs --warnings-as-errors` | Formatting passed, 148 library tests passed, and ExDoc generated the guides. |

The baseline `609ae3b` hook measured 8,183 bytes gzip. The change measures
8,189 bytes against the 8,192-byte limit. Reproduce the measurement with
esbuild 0.25.4 and Python's gzip compressor.

```sh
esbuild assets/js/live_lift/client_hook.js --minify --target=es2022 --format=esm \
  | python3 -c 'import gzip, sys; print(len(gzip.compress(sys.stdin.buffer.read(), mtime=0)))'
```

The [telemetry guide](../telemetry.md#client-error-reporting) describes how an
application can observe the reports using its existing error collector.
