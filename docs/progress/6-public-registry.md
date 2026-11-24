# Phase 6 — Verify installation from public registries

## Registry and artifact evidence

On 2026-11-24, both the public Hex API and HexDocs served
[`live_lift 0.1.0-rc.1`](https://hex.pm/packages/live_lift/0.1.0-rc.1).
GitHub Actions submitted the package and documentation from `ac48734`.
The maintainer approved the staged release. The public Hex tarball matched
the SHA-256 returned by the release API.
See the [publication job](https://github.com/Manuel1471/LiveLift/actions/runs/45337238691/job/138254788731)
and [published documentation](https://live-lift.hexdocs.pm/0.1.0-rc.1/).

Packing `assets/` at `ac48734` produced a `live-lift-assets 0.1.0-rc.1`
tarball with SHA-256 `7541392a5324ec3701939d752b9df2a89460211a9c0256d4a6a3cd9cd12ed253`.
Its hook matches the bytes in the public Hex package. The generated runtime
binding matches SHA-256 of the version, a NUL byte, and the hook bytes.

## Consumer verification

Run from the repository root with the Phoenix 1.8.16 generator, Elixir
1.20.2, OTP 29 and Node 22.15.0.

| Command | Result |
| --- | --- |
| `LIVE_LIFT_REGISTRY_VERSION=0.1.0-rc.1 LIVE_LIFT_NPM_REGISTRY_VERSION= sh test/integration/phoenix_consumer.sh` | Passed. A new Phoenix app fetched the exact version from Hex and passed installer checks, the migration diff, four parity cases, and build and deploy. A local npm tarball passed strict TypeScript, both runtime builds, and version and byte mismatch rejection. |
| Add `LIVE_LIFT_INTEGRATION_IGNITER=1` to the same command | Passed. Igniter previewed and applied changes in a fresh app using the public Hex dependency. The check verified idempotence, preserved custom steps, and kept the original files when installation was blocked by unsupported layouts. Migration, parity and the npm tarball checks passed. |
| `LIVE_LIFT_REGISTRY_VERSION=0.1.0-rc.1 sh test/integration/phoenix_consumer.sh` | Hex install, migration, parity, build and deploy passed. npm returned `E404` for `live-lift-assets@0.1.0-rc.1`. |

The [asset compatibility spike](../asset-compatibility-spike.md) found that
esbuild enforces the runtime link when the generated registry re-exports it.
The mixed run reproduced that check against the compiler from the public
Hex package and a local npm tarball. Phase 6 closes after the same consumer
installs the matching runtime from public npm and passes.
