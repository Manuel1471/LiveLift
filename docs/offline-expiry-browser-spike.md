# Offline action expiry in the browser

## Question

When two actions have different ages at reconnect, does LiveLift drop
only the expired action and recover cleanly from the server snapshot?

## Method

Open the deployed native counter. Disconnect its socket, increment
the count, advance the browser's monotonic clock past the expiry
limit, and then set a label. Reconnect and inspect the actual event
names and sequence numbers on the WebSocket. Compare the rendered
values, the server acknowledgment and the snapshot after replay.
Confirm a new event after recovery.

The clock is installed before navigation so the browser hook observes
the simulated `performance.now()`.
[Playwright clock reference](https://playwright.dev/docs/clock).

## Result

The count remains predicted while disconnected. On reconnect, the
server's fresh snapshot restores the count and the browser replays
only the recent label event. The WebSocket receives that event at
sequence 1. A subsequent connected increment receives sequence 2.
The rendered result and the authoritative snapshot agree.

The first status prototype measured 8,214 gzip bytes. The prior hook
measured 8,189. The implemented hook measures 8,192 with esbuild 0.25.4
and gzip level 9 on macOS and with zlib 1.3.1 in Linux. The budget is
8,192 bytes. The implementation shares sequence validation and status
rendering with existing paths and uses a native `output` element.

The browser test finds the status after the server confirms the recent
action. Thirty checks passed with deployed assets across Chromium,
Firefox and WebKit, covering expiry, reconnect, debounce and view loading.
The expiry check also passed on the development build and on the deployed
build with the fallback parser forced, in all three engines.
The 34 Node runtime tests and 165 ExUnit tests also passed.

```sh
python3 bench/runtime_budget.py "$PWD/examples/demo/_build/esbuild-darwin-arm64"
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/live_lift.spec.mjs e2e/island_loading.spec.mjs \
  --grep 'connection cut|offline action expiry|offline clicks|phx-debounce delays|submit cancels|loading|unavailable|lazy'
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 npm run e2e -- \
  e2e/live_lift.spec.mjs --grep 'offline action expiry'
npm run e2e -- e2e/live_lift.spec.mjs --grep 'offline action expiry'
```

The browser check simulates elapsed browser time. Operating-system
suspension and background timer behavior require platform tests.
Playwright verifies the browser's status role. Screen-reader delivery
still needs manual verification.

## Decision

Show the notice after recovering the authoritative snapshot when at least
one action eligible for replay has expired. The existing queue lifetime,
conflict policy and event sequence rules apply.

## Configured conflict policy

The demo can start with `LIVE_LIFT_DEMO_DISCARD_OFFLINE=1` to set the
application's `reconnect_conflict: :discard` configuration. The browser
test checks the policy present in Phoenix's markup, predicts an increment
and a label change offline, then reconnects to a new server instance.

With `:discard`, both predictions roll back and no offline event crosses
the WebSocket. A new connected increment is accepted as sequence 1.
With the default `:replay_offline`, the increment and label are sent in
order as sequences 1 and 2. The next connected click advances to sequence
3. The browser values agree with the authoritative snapshot in both runs.

```sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/live_lift.spec.mjs --grep 'offline clicks follow'
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_DEMO_DISCARD_OFFLINE=1 npm run e2e -- \
  e2e/live_lift.spec.mjs --grep 'offline clicks follow'
```

CI exercises both settings with digested assets. The test covers a fresh
server instance. Same-instance retries have separate runtime tests.

Against baseline `11c0f8c`, the discard path passed in Chromium, Firefox
and WebKit with both parsers. The default CI selection passed 18 local
checks with deployed assets. In a scratch build, forcing replay while
the app still advertised `:discard` caused Chromium to report an
acknowledged sequence of 2 where the test expected 0. Restoring the
runtime restored the expected behavior. The shared hook remained at
8,192 gzip bytes.
