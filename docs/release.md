# Publish the experimental release

Release `0.1.0-rc.1` ships as a matching pair of packages. The Hex package
`live_lift` contains the compiler and the default copied runtime. The npm
package `live-lift-assets` supplies the same hook and TypeScript declarations
for apps that use npm. A fresh Phoenix app passed both local package paths.
See the [phase 6 verification](progress/6-versioned-assets.md).

## Review the packages

From the verified LiveLift checkout, confirm that `mix.exs` and
`assets/package.json` use the same version, then run the local checks.

```sh
mix docs --warnings-as-errors
mix hex.publish --dry-run --yes
(cd assets && npm pack)
```

The npm command creates `assets/live-lift-assets-0.1.0-rc.1.tgz`. Use that
reviewed tarball for the npm release.

Build both artifacts from the same reviewed commit. A change to the browser hook
changes the compatibility binding, even while the unpublished version
number stays the same. Run
`LIVE_LIFT_INTEGRATION_IGNITER=1 sh test/integration/phoenix_consumer.sh` to
verify both local artifacts in a fresh Phoenix app before publishing.

## Publish Hex from GitHub Actions

A push to `main` submits a new version from `mix.exs` to Hex after the
stable test matrix, browser checks, and pinned LiveView compatibility jobs
pass. The job skips versions already available on Hex. The experimental
LiveView `main` check continues to run as an advisory job.

Set `HEX_API_KEY_2` in the repository's Actions secrets using a Hex key
with permission to publish. The job provides that secret to Hex as
`HEX_API_KEY`. New public packages use staged publishing by default, so
check the Hex dashboard for a pending approval after CI succeeds.
See the [Hex publishing guide](https://hex.pm/docs/publish#staged-publishing).

## Publish the matching npm package

Build the npm tarball from the same commit CI used to submit the Hex
release. Publish from the repository root using the npm maintainer account.

```sh
npm publish ./assets/live-lift-assets-0.1.0-rc.1.tgz --tag next
```

The npm command assigns the prerelease to the `next` distribution tag.
See the [npm distribution-tag documentation](https://docs.npmjs.com/adding-dist-tags-to-packages/).

For a manual Hex release, run `mix hex.publish` and complete authentication
in the CLI. If only the documentation upload needs to be retried, run
`mix hex.publish docs` from the same release commit.

## Verify the public consumer

Confirm that both registries serve the release, then run the consumer check
from the same checkout.

```sh
mix hex.info live_lift 0.1.0-rc.1
npm view live-lift-assets@0.1.0-rc.1 version
LIVE_LIFT_REGISTRY_VERSION=0.1.0-rc.1 sh test/integration/phoenix_consumer.sh
```

The script generates a Phoenix app with an exact Hex requirement and installs
the npm release by version. It runs the documented migration, parity and
asset build and deploy checks without a dependency path to the checkout.
The [versioned asset guide](versioned-assets.md) describes the TypeScript
entry point and build-time compatibility check.
