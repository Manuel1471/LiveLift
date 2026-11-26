# PubSub reconciliation across tabs

## Question

Does an optimistic action still converge when PubSub changes the
authoritative state before the action reaches Phoenix?

## Method and result

Two tabs open the demo's root LiveView in the same PubSub room. The first
starts at five and the publisher starts at seven. The WebSocket proxy
holds the first tab's `double` event. Its browser predicts ten while
Phoenix still has five. A server-only button in the publisher broadcasts
`+10`. The publisher reaches seventeen, and the first tab receives fifteen
from its server while the sequence remains unacknowledged. LiveLift then
reapplies `double` to fifteen and displays thirty.

The proxy sends the held frame twice. The first tab reaches acknowledgment
one and its server snapshot matches thirty. The revision advances once for
PubSub and once for `double`. The publisher stays at seventeen with zero
marked events acknowledged. The test compares each revision with that tab's
initial revision because the URL params take effect at mount.

The demo subscribes with Phoenix PubSub only when a valid `room` parameter
is supplied. It uses synthetic counters and a request-specific topic in
the test. [Phoenix PubSub API](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html).

```sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/live_lift.spec.mjs --grep 'PubSub updates'
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 npm run e2e -- \
  e2e/live_lift.spec.mjs --grep 'PubSub updates'
```

Against `e9983ca`, 36 deployed checks for PubSub, root navigation and
timers passed across Chromium, Firefox and WebKit. The three focused
PubSub checks also passed with the fallback forced. The demo passed its
nine tests and 57 parity cases with both parser configurations. In a
scratch Chromium build, skipping the pending actions displayed fifteen
instead of thirty and made the test fail before the held event was sent.

## Limits and decision

Keep the real server notification in the production-assets test suite.
The test uses two LiveViews on a single Phoenix node and one PubSub
broadcast. It measures the order of reconciliation within that fixture.
