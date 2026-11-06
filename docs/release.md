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
credentials; this workspace's Git CLI currently has none. Do not publish an
older checkout: verify `git log -1 --oneline` shows `42f102b` or later first.

After publishing, verify the registry and a clean consumer:

```sh
mix hex.info live_lift
mix phx.new /tmp/live_lift_hex_check --no-ecto --no-dashboard --no-mailer --no-gettext --no-install
```

In the new app, add `{:live_lift, "~> 0.1.0-rc.1"}` to `deps/0`, then run
`mix deps.get`, `mix live_lift.install`, and `mix assets.build`. Add a client
view and an island using the [integration guide](phoenix-integration.md).
There should be no dependency `path:` to the repository.
