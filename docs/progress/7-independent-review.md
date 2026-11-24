# Phase 7 — Independent review handoff

The review baseline is `cc4f26e`. The handoff includes a source archive
from that commit, a locally built Hex package for inspection, a commit ID
file, and SHA-256 checksums. The Hex archive still declares `0.1.0-rc.1`
because that is the version in the reviewed source. Use the archive as
a local review artifact. The public `0.1.0-rc.1` was built earlier from
`ac48734`.

Run `shasum -a 256 -c SHA256SUMS` after unpacking the handoff. Extract
the source archive into a clean directory to reproduce the tests. The
Hex archive contains the package as a consumer installs it. The source
archive includes the tests and browser fixtures.

## Review surface

| Boundary | Evidence and source |
| --- | --- |
| Snapshot serialization | `lib/live_lift/state.ex` and `lib/live_lift/component.ex`. Check state limits and the fields selected for the HTML snapshot. The app owns authorization and the choice of public fields. |
| HEEx to DOM | `lib/live_lift/template.ex`, `lib/live_lift/template/parser.ex`, and `assets/js/live_lift/client_hook.js`. Follow literals and dynamic values to their DOM sinks. The seeded corpora test the reported parser, diagnostic, and rendering cases. |
| Browser event to server | `lib/live_lift/component.ex` and `assets/js/live_lift/client_hook.js`. Check parameter shape and bounds, sequence handling, and the original handler's authority. |
| Reconnect, draft storage, and rollback | `assets/js/live_lift/client_hook.js`, `assets/js/live_lift/form_drafts.js`, and `docs/sync.md`. Review queue and draft bounds, instance changes and the emergency switch. |
| Observability and release provenance | `docs/telemetry.md` and `.github/workflows/ci.yml`. Review the server metadata, browser reports, scope of the publishing credential and the artifact hash attached to the staged release. |

`docs/security.md` describes the threat model. The phase 7 evidence in
`docs/progress/` lists the tested grammar, CSP scope and browser versions.
An independent report should identify the reviewed commit and scope and
record any findings, how they were resolved, and untested surfaces. The
review remains open until that report is available.

## Reproduce the baseline

Use Elixir 1.20 with OTP 29, Node, and the Phoenix 1.8.16 generator.
From the extracted source root:

```sh
mix archive.install hex phx_new 1.8.16
mix deps.get
npm ci --prefix bench
mix format --check-formatted
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
mix hex.audit
mix docs --warnings-as-errors
mix hex.publish --dry-run --yes
(cd assets && npm test)

(cd examples/demo && mix deps.get && mix hex.audit && mix test)
(cd examples/demo && mix live_lift.test --cases test/live_lift_cases.json && mix assets.setup)

(cd bench && npx playwright install chromium firefox webkit)
(cd bench && npm run e2e)
(cd bench && LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/island_loading.spec.mjs \
  e2e/devtools.spec.mjs e2e/local_actions.spec.mjs e2e/content_security_policy.spec.mjs)

LIVE_LIFT_INTEGRATION_IGNITER=1 LIVE_LIFT_CONSUMER_BROWSER_PORT=4053 \
  sh test/integration/phoenix_consumer.sh
```

The consumer command starts a separate Phoenix app from the packed
library. It checks installer behavior, migration, build and deploy,
browser prediction and server confirmation. The local asset packaging
regression uses a local tarball. Hex remains the public publishing channel.

## Recorded results

On 2026-11-24, the clean source at `1745583` passed 155 tests with
each parser, 34 JavaScript runtime tests, nine demo tests and 56 demo
parity cases. Both Hex dependency audits, ExDoc, the package dry run and
the consumer checks passed. The toolchain was Elixir 1.20.2, OTP 29,
Node 26.5.0 and Playwright 1.65.0 on macOS 26.5.2 (Apple M4).

The full browser run recorded 254 passes, 30 opt-in skips and one
Firefox timeout in the CSP test's response interception. Commit
`cc4f26e` moves that header to Phoenix. The updated test passed 18
repetitions across the three browsers and two asset modes. The targeted
deployed-asset run at `cc4f26e` passed 24 checks, with 12 development
inspector cases skipped by design. The full browser suite has not been
rerun on that commit.

The Hex archive rebuilt from `cc4f26e` matched the original review
artifact byte for byte. Its SHA-256 is
`df91bc65f82368d96304422dfd431211e1b584e81643b5809c5f3762ec49044e`.

## Release verification

The package dry run covers the packaging and documentation checks. The
signed public release gate requires a new GitHub run that stages a package,
signs the staged checksum, and completes approval on Hex. Follow
`docs/release.md` to verify the signed checksum from the downloaded
public tarball.
