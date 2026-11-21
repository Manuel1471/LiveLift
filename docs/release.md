# Publish the experimental release

The prepared version is `0.1.0-rc.1`. The local Hex dry run passed, including
documentation generation. A fresh Phoenix 1.8 app also built and tested with
the unpacked Hex package at `/tmp/live_lift_rc1_package`; this proves the
package contains its runtime, installer and compiler without referring to the
LiveLift source checkout. Fetching from Hex remains untested until publication.

From the LiveLift repository:

```sh
git push origin main
mix hex.publish --yes
```

Hex will ask for your account's one-time code. The first command needs GitHub
credentials; this workspace's Git CLI currently has none. Use the commit that passed the versioned asset checks in the
[phase 6 verification](progress/6-versioned-assets.md).

After publishing, verify the registry and a clean consumer:

```sh
mix hex.info live_lift
mix phx.new /tmp/live_lift_hex_check --no-ecto --no-dashboard --no-mailer --no-gettext --no-install
```

In the new app, add `{:live_lift, "~> 0.1.0-rc.1"}` to `deps/0`, then run
`mix deps.get`, `mix live_lift.install`, and `mix assets.build`. Add a client
view and an island using the [integration guide](phoenix-integration.md).
There should be no dependency `path:` to the repository.

## Check the npm artifact and the public consumer

Use a local tarball for review. The version must match `mix.exs`.

```sh
(cd assets && npm pack)
```

The [versioned asset guide](versioned-assets.md) describes the npm entry point,
TypeScript declarations and build-time compatibility check. Once both packages
are published, run the same Phoenix consumer checks against the registries.

```sh
LIVE_LIFT_REGISTRY_VERSION=0.1.0-rc.1 sh test/integration/phoenix_consumer.sh
```

This route pins the Hex release and installs the npm release by version. The
generated app uses the installer and runs the migration, parity and asset
checks without a dependency path to the source checkout.
