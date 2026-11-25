# Phase 7 — Independent review handoff

The review baseline is `d5a1ffc71bb46a433217b9dadb49835936826fb5`.
The handoff includes a source archive from that commit, a local Hex
package built from the extracted archive, the commit ID, and SHA-256
checksums. The public Hex release `0.1.0-rc.1` was built from `ac48734`.
Use the commit ID to identify the review source because the local
archive also declares `0.1.0-rc.1`.

## Build and verify the handoff

Run this from a Git checkout that contains the review commit.

```sh
review_dir=$(mktemp -d)
commit=d5a1ffc71bb46a433217b9dadb49835936826fb5
mkdir "$review_dir/source"
git rev-parse --verify "$commit^{commit}" >"$review_dir/COMMIT"
git archive --format=tar "$commit" >"$review_dir/source.tar"
gzip -n "$review_dir/source.tar"
tar -xzf "$review_dir/source.tar.gz" -C "$review_dir/source"
(cd "$review_dir/source" && mix hex.build --output "$review_dir/live_lift-review.tar")
(cd "$review_dir" && shasum -a 256 COMMIT source.tar.gz live_lift-review.tar >SHA256SUMS)
printf '%s\n' "$review_dir"
```

The handoff consists of `COMMIT`, `source.tar.gz`, `live_lift-review.tar`,
and `SHA256SUMS`. From the directory containing those files, check
their integrity and compare the commit embedded in the source archive
with the supplied commit and the Git revision above.

```sh
shasum -a 256 -c SHA256SUMS
test "$(gzip -dc source.tar.gz | git get-tar-commit-id)" = \
  "$(cat COMMIT)"
```

For the test commands below, extract `source.tar.gz` into a fresh
directory. It includes the tests and browser fixtures. Use the Hex
archive to inspect the files a consumer installs.

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
(cd examples/demo && sh ../../test/integration/demo_source_maps.sh)

(cd bench && npx playwright install chromium firefox webkit)
(cd bench && npm run e2e)
(cd bench && LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/island_loading.spec.mjs \
  e2e/devtools.spec.mjs e2e/local_actions.spec.mjs e2e/content_security_policy.spec.mjs)
(cd bench && LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- \
  --grep 'connection cut|phx-debounce delays|submit cancels')

LIVE_LIFT_INTEGRATION_IGNITER=1 LIVE_LIFT_CONSUMER_BROWSER_PORT=4053 \
  sh test/integration/phoenix_consumer.sh
```

The consumer command starts a separate Phoenix app from the packed
library. It checks installer behavior, migration, build and deploy,
browser prediction and server confirmation. The local asset packaging
regression uses a local tarball. Hex remains the public publishing channel.

## Earlier baseline

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
inspector cases skipped by design. A fresh extraction of `cc4f26e`
then passed the full browser suite with 255 passes, zero failures and
30 opt-in skips. The Firefox CSP test passed in that run.

The Hex archive rebuilt from `cc4f26e` matched the original review
artifact byte for byte. Its SHA-256 is
`df91bc65f82368d96304422dfd431211e1b584e81643b5809c5f3762ec49044e`.

## Results for the current baseline

On 2026-11-25, two clean extractions of `d5a1ffc` produced the same
local Hex archive byte for byte. The recipe above reproduced the same
manifest. These are the recorded SHA-256 values for the two archives:

| File | SHA-256 |
| --- | --- |
| `source.tar.gz` | `81a31ea659fc668d277d7905b70fc35fea6e9e05f2ab8d71914e4f8f01231c71` |
| `live_lift-review.tar` | `9a5408e1f144ff1b6f4bffe970becfa4e79e4ba6fb5424e9de7bbe407d26e12c` |

The extracted source passed 158 Mix tests with each parser, 34 JavaScript
runtime tests, nine demo tests, and 56 demo handler parity cases across
10 modules. Both Hex dependency audits, ExDoc with warnings as errors,
and the Hex package and docs dry run completed. The dry run reported
an expired local Hex authentication session. The toolchain was Elixir
1.20.2, OTP 29.0.3, Hex 2.5.1 and Node 26.5.0 on macOS 26.5.2 arm64.

The generated Phoenix 1.8.16 app installed the local Hex package with
Igniter. Migration, build and deploy, split source maps, and handler
parity passed. Chromium, Firefox, and WebKit verified a local prediction,
the authoritative save, and both emergency switches. The consumer run
preloaded Tailwind 4.3.3 and esbuild 0.25.4 in its scratch directory.
The demo's deployment regression verified source mapping through esbuild
and the removal of public maps. The shared runtime measured 8,189 gzip
bytes within the existing 8,192-byte budget.

The full Playwright 1.65.0 suite passed 255 checks with 30 opt-in
benchmark cases skipped and zero failures. With deployed assets,
Playwright passed 24 focused checks and skipped 12 development-only
inspector cases. A separate deployed run passed all nine checks for
connection cuts, debounce, and cancellation on submit. These two runs
used a separate local port while the full suite ran. All three runs
used Chromium 158.0.8127.18, Firefox 159.0, and WebKit 27.2.

## Release verification

The package dry run covers the packaging and documentation checks. The
signed public release gate requires a new GitHub run that stages a package,
signs the staged checksum, and completes approval on Hex. Follow
`docs/release.md` to verify the signed checksum from the downloaded
public tarball.
