# Skip decoding an unchanged snapshot

An optimistic island can receive a LiveView hook update with the same revision
and acknowledged sequence. When the hook is outside recovery, it can leave
the current state alone without decoding another JSON copy of it.

## Reproduction

Run from the repository root with Chromium installed through Playwright.

```sh
git show d34d0a6:assets/js/live_lift/client_hook.js > /tmp/livelift-baseline.js
node bench/snapshot_updates.mjs /tmp/livelift-baseline.js
```

The benchmark calls the actual hook's update function 1,000 times per sample
against a fixed, unchanged snapshot. Both versions run in the same Chromium
page, with 10 warmup samples and 40 measured samples per variant. The run
alternates baseline-first and candidate-first order and checks that neither
variant enqueues an unchanged snapshot.

| Rows | State bytes | Baseline median / p95 per 1,000 updates | Candidate median / p95 |
| ---: | ---: | ---: | ---: |
| 100 | 3,291 | 5.9 / 6.0 ms | <0.1 / 0.1 ms |
| 1,000 | 34,791 | 62.4 / 63.9 ms | <0.1 / <0.1 ms |

Local Chromium run on an Apple M4 Mac. Values below 0.1 ms reached the
browser timer's resolution. This isolates repeated hook invocations. A real
LiveView diff, changed state, recovery, DOM reconciliation and network
transport are outside the measurement. The actual savings depend on how
often the app sees an unchanged snapshot.

A separate BEAM experiment replaced `Map.new/2` with `:maps.map/2` for
float wire encoding. Gains varied by payload and did not hold for all p95
samples with floats. The release keeps the existing encoder.

The shared browser hook is 8,183 bytes gzip when minified with esbuild 0.25.4
for ES2022, below the 8,192-byte budget. The local-action adapter appears
only in registries that use it.
