# Phase 6 — TypeScript and versioned browser assets

For contributors verifying the experimental asset delivery.

Phoenix's normal asset path must keep working with the copied runtime.
The optional npm path must bundle a real component from a packed npm
artifact and consume its types in strict TypeScript. Both paths must
reject an incompatible runtime before mounting an island. The shared
runtime must remain within the existing budget.

The [spike](../asset-compatibility-spike.md) compared an unused import
and a re-export. The [decision](../decisions/ADR-0008-link-versioned-assets.md)
uses an ESM re-export linking the generated entry to the release and
content of the selected runtime. Neither ESM linking nor TypeScript
declarations add a check to the running hook.

## Verification

Local on 2026-11-21, macOS arm64, Elixir 1.20.2, OTP 29, Node 26.5.0,
npm 11.17.0, esbuild 0.25.4, and TypeScript 5.9.3. Baseline `4b040fe`.

| Command | Result |
| --- | --- |
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | Passed |
| `mix test`, `LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test` | 146 passed with each parser. Includes a raw Node ESM mismatch check and a custom copied runtime path |
| `npm test` from `assets/` | 34 passed |
| `mix test` and `mix live_lift.test --cases test/live_lift_cases.json` from `examples/demo/` | 9 tests and 44 parity cases passed |
| `mix assets.build`, `mix assets.deploy` from `examples/demo/` | Passed |
| `sh test/integration/phoenix_consumer.sh` | Passed with the Mix installer and the copied runtime |
| `LIVE_LIFT_INTEGRATION_IGNITER=1 sh test/integration/phoenix_consumer.sh` | Built and deployed a fresh Phoenix app using an unpacked Hex artifact and a locally installed npm tarball. Strict TypeScript passed for both runtime routes, Node loaded a generated lazy view, and esbuild rejected both a same-version tarball with changed bytes and a different-version tarball with identical source |
| `npm ci && npm run e2e` from `bench/` | 243 passed across Chromium, Firefox and WebKit, with 24 opt-in benchmarks skipped |
| `LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/island_loading.spec.mjs e2e/devtools.spec.mjs` from `bench/` | 12 passed against the exact final marker with digested assets, with 12 development-only cases skipped |
| `LIVE_LIFT_REGISTRY_VERSION=0.1.0-rc.1 sh test/integration/phoenix_consumer.sh` | Blocked at dependency resolution because the Hex package is absent. The npm registry also returned 404 for the version |

The shared runtime source is byte-identical to the baseline and remains
8,179 bytes gzip with the [reference command](5.2-changeset-form-projection.md).
Two checkout archives were built with the same `mix assets.deploy` command.
All emitted island chunks matched byte for byte, and both minified demo
entries were 180,514 bytes. Python `gzip.compress` at level 9 with
`mtime=0` measured 55,026 bytes for the baseline and 55,029 for the
candidate. The generated binding was absent from both deployed entries.
No latency benchmark was rerun for this build-time check.

The asset check consumes a package version and compiler-owned hook bytes.
Browser state, events, URLs, storage, HTML sinks and telemetry are
unaffected. No new runtime dependency was added. Public registry verification
and hosted CI remain pending.
