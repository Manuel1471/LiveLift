# Phase 6 — Event frequency and interaction latency

The [spike](../event-telemetry-spike.md) verified Phoenix's native span on
both sides of an opt-in and separated the optimistic DOM update from the
authoritative acknowledgment. The [guide](../telemetry.md) shows how an
app can count completed events and collect the same server duration
before and after migration. The browser comparison is isolated in
Playwright. Application JavaScript, server event envelopes and emitted
telemetry events are unchanged.

## Verification

| Command | Result |
|---|---|
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | Passed |
| `mix test` | 137 passed |
| `npm test` from `assets/` | 34 passed |
| `mix test` and `mix live_lift.test --cases test/live_lift_cases.json` from `examples/demo/` | 9 tests and 44 cases passed |
| `mix assets.build` and `mix assets.deploy` from `examples/demo/` | Passed |
| `sh test/integration/phoenix_consumer.sh` | Passed in a fresh Phoenix app |
| `npm run e2e -- event_telemetry.spec.mjs` from `bench/` | 3 passed in development and 3 with digested assets |
| `npm ci && npm run e2e` from `bench/` | 228 passed in Chromium, Firefox and WebKit; 24 opt-in benchmarks skipped |

The test holds the outgoing event and verifies that the optimistic count
moves before its ack sequence. The server test selects module, event and
native duration from Phoenix metadata. Neither check exposes event
parameters, state values, or full telemetry metadata. The browser probe
returns durations only and uses no telemetry transport.

## Browser measurement

Measured locally on 2026-11-21 using Chromium 158.0.8127.18, macOS
arm64 (Apple M4), Elixir 1.20.2, OTP 29, Node 26.5.0 and LiveView 1.2.13.
The baseline uses the demo's plain Phoenix counter. For each run and CPU
profile, the benchmark alternates variants over 100 measured increments
each after five warmups each. Each click settles before the next click.
A fresh Chromium process runs each profile.

```sh
cd bench
LIVE_LIFT_BENCH=1 npm run e2e -- --project=chromium --grep 'benchmark native component click latency'
```

Run the command twice. LiveSocket adds 75 ms to its send and receive
paths for this fixture. The page clock begins immediately before
dispatch. Times below are in milliseconds. A zero reading is within
the clock's resolution.

| Run | CPU | Observation | Min | Median | p95 | Max | IQR |
|---|---|---|---:|---:|---:|---:|---:|
| A | 1x | Server-only DOM | 153.0 | 155.4 | 156.4 | 256.3 | 0.8 |
| A | 1x | Optimistic DOM | 0.3 | 0.6 | 1.0 | 1.1 | 0.2 |
| A | 1x | Optimistic ack | 153.6 | 156.4 | 157.3 | 158.2 | 0.9 |
| A | 4x | Server-only DOM | 150.8 | 152.2 | 153.1 | 153.7 | 0.8 |
| A | 4x | Optimistic DOM | 0.0 | 0.6 | 1.1 | 2.8 | 0.4 |
| A | 4x | Optimistic ack | 151.3 | 152.7 | 153.8 | 156.1 | 0.9 |
| B | 1x | Server-only DOM | 153.7 | 155.5 | 156.4 | 156.7 | 0.8 |
| B | 1x | Optimistic DOM | 0.3 | 0.6 | 0.8 | 1.1 | 0.1 |
| B | 1x | Optimistic ack | 153.9 | 156.6 | 157.6 | 162.5 | 1.0 |
| B | 4x | Server-only DOM | 150.8 | 152.4 | 153.2 | 156.6 | 0.7 |
| B | 4x | Optimistic DOM | 0.0 | 0.5 | 0.9 | 1.1 | 0.5 |
| B | 4x | Optimistic ack | 151.4 | 152.8 | 153.6 | 155.5 | 0.9 |

The counter's optimistic DOM median was 0.5–0.6 ms across the two
runs and CPU settings. The server-only DOM median was
152.2–155.5 ms and the optimistic ack median was
152.7–156.6 ms. The local DOM update avoids waiting for the
confirmation in this scenario. These times describe the counter's DOM
and acknowledgment under simulated latency.

## Phoenix span measurement

Run the [server benchmark from the guide](../telemetry.md#baseline-before-migration)
twice. It uses the Phoenix component stop span, `LiveViewTest`, sequence
numbers for the optimistic route and 100 interleaved events per variant
after 20 warmups. These durations cover Phoenix's component event span
on the same machine as the browser runs. Times are in microseconds.

| Run | Route | Min | Median | p95 | Max | IQR |
|---|---|---:|---:|---:|---:|---:|
| A | Server-only | 0.46 | 0.67 | 2.08 | 2.62 | 0.21 |
| A | Opted-in | 2.50 | 3.12 | 4.96 | 8.12 | 1.08 |
| B | Server-only | 0.38 | 0.67 | 2.29 | 11.00 | 0.25 |
| B | Opted-in | 2.54 | 3.50 | 6.08 | 8.29 | 1.37 |

The same server span increased from a median of 0.67 µs to 3.13–3.50
µs in this fixture. The browser comparison tracks a separate cost
and benefit.
