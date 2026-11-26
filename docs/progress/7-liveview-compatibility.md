# Phase 7 — LiveView compatibility and dependency audit

The compatibility workflow now exercises the same fresh Phoenix consumer
on LiveView 1.2.0 and 1.2.15. The generator, library tests and browser
tests run under the pinned dependency for each job. The consumer applies
the documented migration and checks initial server HTML, immediate
prediction, the server acknowledgment, and an unmarked save using the
deployed assets.

## Local verification

On 2026-11-24, both consumer runs passed on macOS 26.5.2 (arm64), Elixir
1.20.2, OTP 29, Node 26.5.0, and Phoenix generator 1.8.16.

```sh
LIVE_LIFT_LIVE_VIEW_VERSION='== 1.2.0' LIVE_LIFT_CONSUMER_BROWSER_PORT=4047 \
  sh test/integration/phoenix_consumer.sh
LIVE_LIFT_LIVE_VIEW_VERSION='== 1.2.15' LIVE_LIFT_CONSUMER_BROWSER_PORT=4049 \
  sh test/integration/phoenix_consumer.sh
```

Each command passed four parity cases, both asset aliases and the browser
probe in Chromium 158.0.8127.18, Firefox 159.0 and WebKit 27.2.
The workflow config targets Elixir 1.18 and OTP 27 on GitHub-hosted Linux.

Hex reported advisories in the previous locks. Updating both locks to
LiveView 1.2.15, Phoenix 1.8.17 and Plug 1.20.4 resolved the advisories
reported by `mix hex.audit` at the time of verification. LiveView 1.2.0
remains a compatibility test fixture. See the
[Phoenix LiveView advisories](https://hex.pm/packages/phoenix_live_view/advisories).

With the updated locks, `mix test` passed 148 cases in the library and
9 in the demo. The demo passed 56 handler parity cases and 15 targeted
browser tests for event measurement, split asset loading and local
actions using deployed assets. The local Igniter and asset packaging
regression checks also passed.

## Weekly upstream check

The `LiveView main advisory` workflow runs Mondays at 14:37 UTC and can
also be started manually. CI reuses it for pushes and pull requests.
It records the resolved LiveView commit, runs both parser paths, and
executes the LiveView API spike. The fallback and API checks still run
if the first parser check fails after setup.

Failures on pushes and pull requests produce an annotation and a run
summary. Scheduled and manual failures also produce a failed workflow
status. GitHub sends scheduled-run notifications according to the
associated user's settings. The schedule takes effect on the default
branch. [GitHub workflow notifications](https://docs.github.com/en/actions/concepts/workflows-and-actions/notifications-for-workflow-runs).

From a disposable checkout, run the same steps with `main` selected.

```sh
export LIVE_LIFT_LIVE_VIEW_VERSION=main
mix deps.get
git -C deps/phoenix_live_view rev-parse HEAD
npm ci --prefix bench
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
mix run spikes/liveview_api.exs
```

On 2026-11-25, the upstream check resolved LiveView
`62674c2226ada1770c8d5e10920014c9a9e4b091`. All 168 tests passed per
parser configuration and the LiveView API spike passed. This local run
used Elixir 1.20.2, OTP 29.0.3 and Node 26.5.0 on macOS arm64.

The hosted [CI run for `c65ae03`](https://github.com/Manuel1471/LiveLift/actions/runs/45739320913)
also passed. Its [upstream job](https://github.com/Manuel1471/LiveLift/actions/runs/45739320913/job/139640162048)
recorded the upstream revision and passed both parser steps and the API spike.
Both pinned LiveView compatibility jobs passed their demo parser comparison
and fresh Phoenix consumer checks. The run was triggered by a push. The
scheduled workflow had zero runs when checked on 2026-11-25.
