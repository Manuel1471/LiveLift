# Publish the experimental release

Publish LiveLift to Hex. The `live_lift` package includes the compiler,
browser runtime, and TypeScript declarations. The Phoenix installer copies
the browser assets from the installed dependency.

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
`HEX_API_KEY`. New public packages use staged publishing by default, so
check the Hex dashboard for a pending approval after CI succeeds.
See the [Hex publishing guide](https://hex.pm/docs/publish#staged-publishing).

For a manual release, run `mix hex.publish` and complete authentication in
the CLI. If only the documentation upload needs to be retried, run
`mix hex.publish docs` from the same release commit.

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
