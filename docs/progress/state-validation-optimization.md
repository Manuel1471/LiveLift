# State validation optimization

The server builds a diagnostic path only on error and visits list items
without allocating indexed pairs. The browser uses the character count
of validated ASCII map keys and tagged float text. It continues to count
arbitrary strings with UTF-8 encoding. New boundary checks exercise
Unicode and a signed-zero float exactly at the byte limit, then reject
one extra byte. A nested invalid UTF-8 test checks the original path.

## Reproduce

Measured locally on 2026-11-22 on Apple M4 macOS arm64 using Elixir
1.20.2, OTP 29, Node 26.5.0, esbuild 0.25.4 and Chromium
158.0.8127.18. Baseline commit `1554ad7`.

```sh
git show 1554ad7:lib/live_lift/state.ex > /tmp/lift-baseline-state.ex
git show 1554ad7:assets/js/live_lift/client_hook.js > /tmp/lift-baseline-hook.js
mix run bench/state_validation.exs /tmp/lift-baseline-state.ex
(cd bench && node browser_state_validation.mjs /tmp/lift-baseline-hook.js)
(cd bench && LIVE_LIFT_BENCH=1 npm run e2e -- --project=chromium row_edit_profile.spec.mjs)
```

Repeat each isolated comparison. BEAM interleaves 300 samples per
variant and row count after 30 warmups. Chromium interleaves 100 batches
per variant and row count after 20 warmups. Each timed batch averages
16 successive validations, with a fresh browser for each CPU rate. These
comparisons reuse the input object and time validation. The browser
fixture includes non-ASCII labels. Results below report min, median,
p95, max and IQR in that order. See the
[spike](../state-validation-profile-spike.md) for the separate live profile.

## Paired validation results

| Runtime | Run | Rows | Baseline | Candidate |
| --- | --- | ---: | --- | --- |
| BEAM (µs) | A | 100 | 136.3 / 167.4 / 184.1 / 205.2 / 17.8 | 104.0 / 128.9 / 142.7 / 153.3 / 12.4 |
| BEAM (µs) | A | 1000 | 1359.5 / 1453.0 / 1552.8 / 1679.2 / 47.6 | 1056.0 / 1164.8 / 1217.5 / 1344.7 / 45.7 |
| BEAM (µs) | B | 100 | 132.1 / 156.6 / 172.2 / 188.8 / 18.7 | 112.1 / 126.0 / 136.2 / 150.9 / 7.9 |
| BEAM (µs) | B | 1000 | 1427.6 / 1506.6 / 1582.8 / 1708.5 / 41.3 | 1111.5 / 1258.2 / 1298.4 / 1323.0 / 39.2 |
| Chromium 1x (ms) | A | 100 | 0.112 / 0.125 / 0.419 / 2.306 / 0.006 | 0.056 / 0.069 / 0.075 / 0.606 / 0.006 |
| Chromium 1x (ms) | A | 1000 | 1.325 / 1.487 / 3.888 / 4.062 / 0.400 | 0.725 / 0.775 / 3.019 / 3.213 / 0.300 |
| Chromium 4x (ms) | A | 100 | 0.413 / 0.506 / 1.075 / 2.306 / 0.031 | 0.213 / 0.269 / 0.600 / 2.950 / 0.031 |
| Chromium 4x (ms) | A | 1000 | 5.062 / 5.850 / 8.456 / 9.619 / 1.506 | 2.769 / 3.081 / 5.719 / 7.587 / 0.969 |
| Chromium 1x (ms) | B | 100 | 0.112 / 0.131 / 0.463 / 2.344 / 0.012 | 0.062 / 0.069 / 0.081 / 1.019 / 0.006 |
| Chromium 1x (ms) | B | 1000 | 1.362 / 1.675 / 4.513 / 5.200 / 2.087 | 0.737 / 0.862 / 3.831 / 4.531 / 0.363 |
| Chromium 4x (ms) | B | 100 | 0.475 / 0.556 / 1.450 / 4.394 / 0.038 | 0.237 / 0.294 / 0.331 / 2.856 / 0.031 |
| Chromium 4x (ms) | B | 1000 | 5.644 / 6.494 / 9.081 / 10.831 / 2.362 | 3.000 / 3.231 / 6.000 / 7.525 / 0.975 |

The isolated 1,000-row validation median fell about 16–20% on BEAM
and 47–50% in Chromium. These measurements cover validation only.

## Live row profile

These are separate baseline and candidate recordings. Each run has ten
warmups and 100 timed edits per fixture. Timing varies across runs and
includes work outside the changed validator. Use the paired validation
measurements above to assess the isolated improvement.

| Build | CPU | Rows | Local edit (ms) | Acknowledgment (ms) |
| --- | ---: | ---: | --- | --- |
| Baseline | 1x | 100 | 0.3 / 0.5 / 0.6 / 3.5 / 0.1 | 2.1 / 2.5 / 5.2 / 8.8 / 1.0 |
| Baseline | 1x | 1000 | 3.1 / 4.1 / 19.4 / 25.8 / 0.5 | 20.2 / 24.9 / 46.8 / 77.0 / 13.3 |
| Baseline | 4x | 100 | 1.3 / 2.5 / 3.2 / 4.8 / 0.6 | 8.7 / 17.4 / 25.6 / 32.5 / 3.1 |
| Baseline | 4x | 1000 | 12.3 / 17.2 / 34.9 / 41.3 / 1.9 | 86.2 / 101.1 / 180.9 / 220.0 / 24.2 |
| Candidate | 1x | 100 | 0.3 / 0.4 / 0.5 / 0.6 / 0.1 | 2.1 / 2.4 / 3.6 / 5.3 / 0.7 |
| Candidate | 1x | 1000 | 2.6 / 3.0 / 12.0 / 14.4 / 0.2 | 19.0 / 21.2 / 37.3 / 47.9 / 7.6 |
| Candidate | 4x | 100 | 1.0 / 1.8 / 2.5 / 9.9 / 0.5 | 7.7 / 16.0 / 20.1 / 24.4 / 2.7 |
| Candidate | 4x | 1000 | 10.9 / 13.1 / 24.4 / 37.7 / 1.2 | 81.8 / 91.8 / 144.7 / 168.6 / 12.2 |

Each 1,000-row acknowledgment exposed 34,867 bytes of projected state
in the fixture. This is the JSON state size in the DOM.

## Size and compatibility

The shared hook went from 27,312 to 27,282 minified bytes and from
8,179 to 8,178 gzip bytes. Both used the repository reference command
with esbuild ESM for ES2022 and Python gzip level 9 with `mtime=0`.

The same validation limits, error locations, and server authority apply.
The optimization consumes no additional input sources and changes
neither the wire format nor rendering. The changed byte accounting runs
after the existing key or float syntax check.

The reference initial JavaScript benchmark now applies the production
inspector define. Its eager output went from 64,478 to 64,469 gzip bytes,
and its split output went from 55,365 to 55,361, with nine deferred chunks
in both split runs. This uses the same demo, baseline hook and compiler
asset-link code.

The existing reference scripts were also run. Their fixtures and methods
differ from the paired comparison above.

| Command | Result |
| --- | --- |
| `mix run bench/benchmark.exs` | 100 renders per size and 10,000 actions per runtime. The 1,000-row render measured 925.9 µs median and 1,085.8 µs p95 |
| `sh bench/phoenix_bundle.sh` | Generated Phoenix app measured 47,351 gzip bytes alone and 55,843 with the reference island |
| `sh bench/phoenix_event.sh` | Five runs of 200 events per variant. Median of the run medians was 46 µs in plain Phoenix and 54 µs with the reference island |
| `npm run dom` from `bench/` | 50 linkedom samples per size. The 1,000-row reverse measured 2.24 ms median and 4.84 ms p95. This measures the DOM model |
| `python3 bench/island_bundle.py` | Both eager and split outputs measured for baseline and candidate |

## Verification

| Command | Result |
| --- | --- |
| `mix format --check-formatted`, `mix compile --warnings-as-errors` | Passed |
| `mix test` and `LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test` | 147 passed per parser |
| `npm test` from `assets/` | 34 passed |
| `mix test`, demo parity, `mix assets.build`, and `mix assets.deploy` | 9 tests and 44 parity cases passed. Both asset commands passed |
| Both fresh Phoenix consumer routes | Passed with the copied runtime, the local Hex and npm artifacts, TypeScript and incompatible-runtime checks |
| `npm ci && npm run e2e` from `bench/` | 243 passed. 30 opt-in benchmark cases skipped |
| `LIVE_LIFT_BENCH=1 npm run e2e -- --project=chromium row_edit_profile.spec.mjs` from `bench/` | Both profiles passed for baseline and candidate. Focus and input identity were preserved |
| Focused deployed browser compatibility suite | 12 passed across Chromium, Firefox and WebKit, covering row correction, reconnect, forms and tagged floats |
