# Publish the experimental release

Release `0.1.0-rc.1` is a matching pair of public packages. The Hex package
`live_lift` contains the compiler and the default copied runtime. The npm
package `live-lift-assets` supplies the same hook and TypeScript declarations
for apps that use npm. A fresh Phoenix app passed both local package paths.
See the [phase 6 verification](progress/6-versioned-assets.md).

## Review the packages

From the verified LiveLift checkout, confirm that `mix.exs` and
`assets/package.json` use the same version, then run the local checks.

```sh
mix hex.publish --dry-run
(cd assets && npm pack)
```

The npm command creates `assets/live-lift-assets-0.1.0-rc.1.tgz`. Use that
reviewed tarball for the npm release.

Build both artifacts from the same commit. A change to the browser hook
changes the compatibility binding, even while the unpublished version
number stays the same.

## Publish with the maintainer accounts

From the repository root, run each command under the corresponding
maintainer account. Complete any authentication prompts directly in the CLI.

```sh
mix hex.publish
npm publish ./assets/live-lift-assets-0.1.0-rc.1.tgz --tag next
```

The npm command assigns the prerelease to the `next` distribution tag.
See the [npm distribution-tag documentation](https://docs.npmjs.com/adding-dist-tags-to-packages/).

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
