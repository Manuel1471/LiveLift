# Browser timer delays

## Question

Do marked LiveView timers converge once when the browser wakes up after
the deadline or when the server commits before the browser callback runs?

## Method and result

Two checks use the demo's root LiveView. Each scheduled timer adds ten.

- Hold two requests at the WebSocket and advance the browser clock past
  both deadlines. The predicted count advances from zero to twenty.
  Another jump leaves it at twenty. Forward both requests, including a
  duplicate of the first. Phoenix confirms sequence 2 and revision 4,
  sends an empty timer snapshot, and agrees with the displayed count.
- Delay the browser callback scheduled by a single click and allow Phoenix
  to process the request. Phoenix commits ten while the browser callback
  is still pending. After a clock jump past the delayed deadline, the
  callback has run zero times and the displayed count still matches.

The first check uses Playwright's clock jump, which runs each due timer
at most once. The second intercepts the fixture's 250 ms callback and
preserves its timeout handle so the app can cancel it.
[Playwright clock reference](https://playwright.dev/docs/api/class-clock#clock-fast-forward).

```sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/timer_lifecycle.spec.mjs
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 npm run e2e -- \
  e2e/timer_lifecycle.spec.mjs --grep 'fast-forward|delayed browser timer'
```

Against baseline `3b9812a`, 24 lifecycle checks and six focused checks
with the alternate parser passed in Chromium 158.0.8127.18, Firefox 159.0
and WebKit 27.2. The shared hook measured 8,192 gzip bytes. The run used
Playwright 1.65.0, Elixir 1.20.2, OTP 29.0.3 and Node 26.5.0 on macOS arm64.

In a scratch build, removing timeout cancellation caused the Chromium
check to observe one delayed callback after Phoenix had committed. The
normal runtime canceled it before the clock advanced past its deadline.

## Limits and decision

The clock jump and delayed callback simulate scheduling delays. Actual OS
suspension and browser-specific background-tab policies require platform
checks. The two new cases cover the root LiveView's additive timer. The
rest of the lifecycle suite covers LiveComponents as well. CI runs that
suite with digested assets and the tests use the existing timer policy.
