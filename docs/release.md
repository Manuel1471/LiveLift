# Publish the experimental release

Publish LiveLift to Hex. The `live_lift` package includes the compiler,
browser runtime, and TypeScript declarations. The Phoenix installer copies
the browser assets from the installed dependency.

## Versioning and deprecations

LiveLift uses semantic versioning. Before 1.0, bump the minor version for
incompatible public API changes. After 1.0, use a major version. Patch
releases fix existing behavior. Use a prerelease suffix such as `-rc.2`
while evaluating a candidate. The [compatibility guide](production-readiness.md#compatibility)
identifies the supported LiveView range and the versions exercised in CI.

Document deprecations in the changelog with the first affected version,
the replacement, and a migration link. Keep the old entry point callable
and issue a compiler warning where possible. Announce removal in advance
and schedule it for a release that permits incompatible changes.

The legacy `use LiveLift.Client` API and `LiveLift.View.island/1` have
issued deprecation warnings since `0.1.0-rc.1`. Migrate to `use LiveLift`
in a Phoenix LiveComponent and mark eligible handlers. Follow the
[migration guide](liveview-migration-diff.md) to opt in and verify behavior
against LiveView. There is no scheduled removal version.

## Prepare the release notes

Add user-facing changes under `## Unreleased` in `CHANGELOG.md`. Use
third-level headings to group those changes. After bumping the version in
`mix.exs`, move the pending notes to that version with:

```sh
elixir scripts/release_notes.exs prepare
elixir scripts/release_notes.exs check
```

The preparation command also updates `assets/package.json` with npm so
the local asset package continues to match the version embedded in the
Hex runtime. Use OTP 27 or newer and the project's Node toolchain.
Review and commit those changes with the version bump. CI checks the
manifest and the newest changelog section against `mix.exs`, then adds
the notes to the publishing job summary before submitting to Hex.

## Review the package

From the verified LiveLift checkout, run the documentation and package checks.

```sh
mix docs --warnings-as-errors
mix hex.publish --dry-run --yes
sh test/integration/phoenix_consumer.sh
```

## Publish Hex from GitHub Actions

A push to `main` submits a new version from `mix.exs` to Hex after the
stable test matrix, browser checks, and pinned LiveView compatibility jobs
pass. The job skips versions already available on Hex. The experimental
LiveView `main` check continues to run as an advisory job.

Set `HEX_API_KEY_2` in the repository's Actions secrets using a Hex key
with permission to publish. The job provides that secret to Hex as
`HEX_API_KEY`. Keep staged publishing enabled for `live_lift`. The job
signs a GitHub build provenance attestation for the exact package SHA-256
that Mix reports after staging. Approve the pending release in Hex after
the GitHub job succeeds and the package SHA-256 matches the job output.
See the [Hex publishing guide](https://hex.pm/docs/publish#staged-publishing).

For a manual release, run `mix hex.publish` and complete authentication in
the CLI. If only the documentation upload needs to be retried, run
`mix hex.publish docs` from the same release commit.

## Verify a signed release

Set `version` to a release staged and attested by the GitHub workflow.
Download the package that Hex serves and verify the attestation against
LiveLift's release workflow:

```sh
archive="live_lift-$version.tar"
curl --fail --silent --show-error --output "$archive" \
  "https://repo.hex.pm/tarballs/$archive"
gh attestation verify "$archive" --repo Manuel1471/LiveLift \
  --signer-workflow Manuel1471/LiveLift/.github/workflows/ci.yml \
  --source-ref refs/heads/main
```

The attestation covers the Hex package archive. HexDocs is submitted by
the same staging command. See the [GitHub CLI verification guide](https://cli.github.com/manual/gh_attestation_verify).

## Verify the public Hex installation

Install the Phoenix 1.8.16 generator if it is unavailable locally.

```sh
mix archive.install hex phx_new 1.8.16
mix hex.info live_lift 0.1.0-rc.1
LIVE_LIFT_REGISTRY_VERSION=0.1.0-rc.1 sh test/integration/phoenix_consumer.sh
```

The script creates a fresh Phoenix app with an exact Hex requirement and
runs the documented migration, parity, asset build, and deploy checks. Add
`LIVE_LIFT_INTEGRATION_IGNITER=1` to verify the Igniter installer.

For browser coverage, install Playwright and its browsers with
`cd bench && npm ci && npx playwright install chromium firefox webkit`.
From the repository root, add `LIVE_LIFT_CONSUMER_BROWSER_PORT=4047` to
the consumer command and use a free local port. The check serves the assets
from `mix assets.deploy` and verifies the initial HTML, the predicted DOM
update, the server acknowledgment, and a server-only save.
