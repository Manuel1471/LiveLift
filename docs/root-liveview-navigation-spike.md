# Root LiveView navigation and tab isolation

## Question

Does each root LiveView keep its own instance and acknowledgments across
browser history, reload, and two open tabs at the same URL?

## Method

Use the routed native timer demo with a starting count that Phoenix
reads from the URL. Test actual LiveView navigation and the browser
history buttons. Hold one event on its browser WebSocket to observe
the local prediction before Phoenix receives it. Verify the URL, visible
count, instance identity and acknowledgment at each step.

Open a second page in the same browser context at the exact same URL.
Hold a prediction in the first tab while the second receives its own
confirmations. Release the held event and reload the other tab. Compare
both instances against the server-provided starting count and their own
events.

## Result

Phoenix merges data attributes when it patches the hook root, including
roots inside a LiveView. The initial readiness marker can disappear on
an ordinary patch. The spike checks readiness on mount and uses the
rendered value, authoritative snapshot and acknowledgment after updates.

With a starting URL of `/native-timer?start=7`, the test confirmed one
increment and held the next. The browser displayed 9 while the server
snapshot stayed at 8. Back navigation restored 7 with a new instance
and acknowledgment zero. Forward navigation remounted the component
counter, which accepted a new event. A marker on the original document
survived both navigations.

The separate tab with the same URL and session confirmed two events
while the first tab's increment remained pending. Releasing that event
confirmed it in the first tab. Reloading the second tab restored its
URL count and started a new acknowledgment sequence while the first
tab kept its instance and confirmed count.

On 2026-11-25, source baseline `6478973` with this change passed six
navigation checks in each asset and parser configuration below. The
deployed timer suite added 18 passing checks. The demo passed nine Mix
tests and 57 handler parity cases. The runs used LiveView 1.2.15, Elixir
1.20.2, OTP 29.0.3, Node 26.5.0 and Playwright 1.65.0 on macOS arm64.
The browser versions were Chromium 158.0.8127.18, Firefox 159.0 and
WebKit 27.2. CI is configured to include the navigation cases in its
development and deployment checks.

```sh
cd bench
npm run e2e -- e2e/root_navigation.spec.mjs
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- \
  e2e/root_navigation.spec.mjs e2e/timer_lifecycle.spec.mjs
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 npm run e2e -- \
  e2e/root_navigation.spec.mjs
```

The demo reconstructs its starting count from the URL. Application
persistence and inter-tab broadcasting depend on the app's server
state and are separate from this instance and acknowledgment check.
