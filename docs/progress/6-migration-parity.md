# Phase 6 — CI parity for a migrated Phoenix app

## Acceptance

Run `mix live_lift.test --cases` in a fresh Phoenix consumer with
a native component and a native root LiveView. Cover both timer routes,
Unicode, nil state and a safe-integer boundary. The CI command must
fail when a marked event or an opted-in module is missing. Unit fixtures
must also prove that differing wire types and a declared timer which
never enters the authoritative queue fail parity. Keep the existing
cases schema and browser protocol.

## What the tests established

The former task compared decoded JSON with numeric coercion and
simulated Elixir timer effects from the declared timer spec. A
fixture with an untagged float and an equal-looking integer could
compare equal. Another fixture declared a timer but never scheduled
it, yet its simulated delayed state matched JavaScript.

Running the updated task tests with only the previous task module
loaded from `dc54f18` produced exactly two failures. Both negative
fixtures had been accepted by that version.

The task now compares the decoded JSON types exactly. It also takes
the actual scheduled entry from the authoritative socket, drives its
normal callback with the queued token, and requires the callback to
consume the entry. It computes the delayed projection without waiting
for wall-clock delivery. Browser tests cover timer delivery and
reconnection separately.

The consumer script uses the existing cases mode as a CI gate.
It generates a complete manifest and two incomplete manifests, then
checks the real exit status and diagnostic for each. See the
[native component guide](../native-livecomponent.md) for the command.

## Verification

Local verification on 2026-11-21 used Elixir 1.20.2, OTP 29, Node
26.5.0 and Phoenix LiveView 1.2.13 on macOS arm64.

| Command | Result |
|---|---|
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | Passed |
| `mix test` and `LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test` | 139 passed per parser |
| `npm test` from `assets/` | 34 passed |
| `mix test` and `mix live_lift.test --cases test/live_lift_cases.json` from `examples/demo/` | 9 tests and 44 parity cases passed |
| `mix assets.build` and `mix assets.deploy` from `examples/demo/` | Passed |
| `sh test/integration/phoenix_consumer.sh` | 3 parity cases across 2 modules, both missing-coverage manifests rejected, assets built and deployed |
| `LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- --grep 'timer\|mailbox\|handler locally'` from `bench/` | 33 passed in Chromium, Firefox and WebKit |
| `npm ci && npm run e2e` from `bench/` | 228 passed in three browsers; 24 opt-in benchmarks skipped |

`python3 bench/island_bundle.py` measured 55,364 bytes gzip for the
split demo entry and 64,477 eager. The shared runtime file is
byte-identical.
