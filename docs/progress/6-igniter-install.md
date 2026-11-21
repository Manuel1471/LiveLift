# Phase 6 — Install with Igniter

For contributors verifying the experimental Phoenix installer.

The Igniter route must work against a built package and a fresh Phoenix
app. It must preview changes, preserve the existing build steps and
comments, install each entry once, and leave the asset files untouched
when the hook or the bundler is unsupported. The ordinary Mix installer
must still work in a project without Igniter.

The [spike](../igniter-install-spike.md) tested optional task dispatch in a
real Phoenix app. The [decision](../decisions/ADR-0007-optional-igniter-install.md)
keeps Igniter in the consumer's development toolchain. The source edit adds
a compile task before a recognized esbuild command in each literal alias
list. JavaScript keeps the original supported colocated hook layout.

## Verification

Local on 2026-11-21 with Phoenix generator 1.8.16, Igniter 0.8.5,
Elixir 1.20.2, OTP 29 and Node 26.5.0 on macOS arm64. Base `19ee81d`.

| Command | Result |
| --- | --- |
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | Passed without Igniter in the project |
| `mix test`, `LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test` | 144 passed in each parser mode |
| `npm test` from `assets/` | 34 passed |
| `mix test`, `mix live_lift.test --cases test/live_lift_cases.json`, `mix assets.build`, `mix assets.deploy` from `examples/demo/` | 9 tests and 44 parity cases passed; both asset aliases succeeded |
| `sh test/integration/phoenix_consumer.sh` | The plain Mix installer, documented component migration, parity and assets succeeded |
| `LIVE_LIFT_INTEGRATION_IGNITER=1 sh test/integration/phoenix_consumer.sh` | Passed from an unpacked local Hex artifact. Asserted the asset preview, two identical installs, comment and custom command preservation, no partial asset writes on two invalid layouts, and a nonzero `--check` exit for an unsupported alias. Migration, parity, build and deploy passed in the consumer. |
| `npm ci && npm run e2e` from `bench/` | 243 passed in Chromium, Firefox and WebKit; 24 opt-in benchmarks skipped |

Igniter 0.8.5 prints source issues and skips the write when a normal
install encounters an unsupported layout. Its normal command can exit
successfully in this case. The integration verifies the issue and
unchanged files directly and checks the failing status with `--check`.

The diff only adds build-time installer code. The browser source and
generated code paths are unchanged. The shared runtime remains 8,179 bytes
gzip by the reference method documented in the
[inspector verification](6-state-inspector.md). No new latency benchmark
was required.

Security review found no new runtime input, state authority change,
telemetry, storage, URL handling or DOM sink. The installer rewrites
known source entries and only reads literal Mix commands. It does not
evaluate arbitrary asset aliases.

The CI entry was parsed locally. Hosted CI and installation from the
public package registry depend on pushing and human publication.
