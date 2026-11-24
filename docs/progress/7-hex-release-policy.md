# Phase 7 — Version policy and release notes

The [release guide](../release.md) defines versioning, deprecation notices
and migration expectations. The published `0.1.0-rc.1` warns when an app
opts into the legacy macros and continues to run them.

On 2026-11-24, on macOS 26.5.2 (arm64), Elixir 1.20.2 and OTP 29,
`elixir scripts/release_notes.exs check` printed the existing
`0.1.0-rc.1` release section. In a temporary copy of `mix.exs` and
`CHANGELOG.md`, a bump to `0.1.0-rc.2` failed validation until
`elixir scripts/release_notes.exs prepare` moved the pending notes.
The command preserved the existing release text byte for byte and left
an empty Unreleased section. The check rejected empty or duplicate
release sections. Repeating preparation reported an error and left the
changelog intact.

The publishing job writes the checked release notes to the GitHub Actions
summary and only attempts a publication after that step succeeds.
Verification through a hosted release run remains pending.

## Prerelease rehearsal

On 2026-11-24, a temporary bump to `0.1.0-rc.2` exposed an outdated
version in the local asset manifest. The generated views asked esbuild
for a runtime binding derived from the new Mix version. Packing the
unchanged manifest produced a different binding and esbuild rejected it.

Release preparation now aligns the local asset manifest and writes the
changelog section. The check rejects a manifest that differs from Mix.
In the same prerelease rehearsal, esbuild bundled the generated views
with the synchronized package. The regression test verifies the
version and notes before and after preparation. The version bump and
the locally packed assets are confined to the rehearsal.

## Signed package workflow

A local probe compared `mix hex.build` with the bytes returned by Hex's
tar builder during `mix hex.publish --dry-run --yes`. The contents archive
matched, while a different metadata key order changed the outer SHA-256.
The workflow therefore uses the checksum emitted for the accepted staged
package, instead of signing a separately built archive.

The checksum extractor accepted a staged package receipt alongside a docs
receipt and rejected missing, malformed, and duplicate package checksums
using local fixtures. The workflow grants attestation permissions to the
existing main-only Hex job and uses a pinned GitHub action to attest the
selected digest. The maintainer checks the staged checksum before approving.

The currently published `0.1.0-rc.1` predates this workflow. The remaining
verification is a hosted run on a new release and a successful
`gh attestation verify` on the package downloaded from the public Hex
registry after approval. The [release guide](../release.md#verify-a-signed-release)
records the verification command.
