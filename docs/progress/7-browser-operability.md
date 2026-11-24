# Phase 7 — Accessibility and 100 components

On 2026-11-24 the demo at baseline `54a46df`, with the updated browser
checks in this delivery, ran on an Apple M4 with macOS 26.5.2, Elixir
1.20.2, OTP 29, Node 26.5.0 and Playwright 1.65.0.

```sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/live_lift.spec.mjs \
  --grep 'focused keyed input|WCAG A or AA|100 opted-in islands'
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_BENCH=1 npm run e2e -- --project=chromium \
  --grep 'benchmark navigation and mount with 100 islands'
```

Nine checks passed with deployed assets in Chromium 158.0.8127.18,
Firefox 159.0 and WebKit 27.2. The keyed list kept the focused input after
reordering. The demo home page passed the axe checks tagged WCAG 2.0 and
2.1 A and AA. These checks cover automated rules and focus in the selected
fixture. Assistive technology testing remains pending.

The 100-component page received events in components 1, 50 and 100.
All three advanced their output and server revision to one. The outputs
and revisions of the other 97 stayed at zero.

## Navigation and mount

The benchmark starts the Node clock before each full navigation and waits
until the LiveView join is complete and all 100 components are in the DOM.
In client mode it also waits for all 100 hooks to report ready. It uses the
same Chromium page, alternates which variant runs first, and discards
five warmups before recording 25 samples per variant. It reports the
nearest-rank percentile and the interquartile range.

| Mode | Median (ms) | p95 (ms) | IQR (ms) |
| --- | ---: | ---: | ---: |
| Server-only | 49.8 | 56.1 | 1.4 |
| LiveLift | 63.4 | 81.0 | 0.9 |

This run includes the full local navigation and mount path, including
the LiveView join and the browser's readiness check. It provides a
comparison for this demo and environment. It does not isolate hook CPU
or measure concurrent traffic.
