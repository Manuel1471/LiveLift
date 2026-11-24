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
