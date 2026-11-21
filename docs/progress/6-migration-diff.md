# Phase 6 — Migration by diff

The guide starts with a working, server-only Phoenix component. The
consumer integration must audit it before opt-in, run a server test,
apply the guide's exact patch, and rerun the same counter and save
assertions with the LiveLift hook. The complete parity manifest and
both asset aliases must still pass. The published diff must leave the
template, mount and handler bodies unchanged.

The [published diff](../liveview-migration-diff.md) is the input to
`git apply` in the consumer check. The test asserts that the patch
only adds one `use LiveLift` line and two `@client true` markers.
The server-only app verifies the rendered count and save result.
The same interaction with the opt-in verifies those values from the
authoritative snapshot received by the hook. ExUnit's LiveViewTest
does not run the generated JavaScript; the existing browser suite
exercises that path in the demo.

The workflow registers the consumer check on its OTP 29 job and
installs the same Phoenix generator that the local check used.
The workflow change was parsed locally. Its hosted execution
requires a branch or pull request.

## Verification

Local run on 2026-11-21 with Phoenix installer 1.8.16, Elixir 1.20.2,
OTP 29 and Node 26.5.0 on macOS arm64.

| Command | Result |
|---|---|
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | Passed |
| `mix test` | 139 passed |
| `npm test` from `assets/` | 34 passed |
| `mix test` and `mix live_lift.test --cases test/live_lift_cases.json` from `examples/demo/` | 9 tests and 44 parity cases passed |
| `mix assets.build` and `mix assets.deploy` from `examples/demo/` | Passed |
| `sh test/integration/phoenix_consumer.sh` | Passed on server and opted-in paths; the exact published diff applied, parity and coverage guards passed and both asset aliases ran |
| `npm ci && npm run e2e` from `bench/` | 228 passed across Chromium, Firefox and WebKit; 24 opt-in benchmarks skipped |
