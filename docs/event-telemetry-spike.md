# Native event measurement spike

## Question

Can an app measure the same event before and after enabling LiveLift
using Phoenix's published span and browser DOM observations?

## Method and acceptance

Send the same counter event to the demo's server-only and opted-in
components. Attach to Phoenix's event stop span and the existing LiveLift
wrapper event. Verify event counts and duration types using only module,
event, marked mode and outcome. Confirm the browser can distinguish
when the count updates from when Phoenix acknowledges it. A browser probe
will use the page's own clock and collect timestamps, without sending any
measurement, payload, or state over the socket.

Report DOM update and authoritative acknowledgment separately.
Warm up each variant, interleave samples, and run normal and throttled
Chromium. The probe measures a specific DOM transition and an
acknowledgment for one interaction. It cannot establish screen paint
time or production latency.

## Result

The [server test](https://github.com/Manuel1471/LiveLift/blob/main/examples/demo/test/live_lift_demo_web/live/event_telemetry_test.exs)
saw the same Phoenix component span on both routes. Two increments on
the server-only component produced two spans. On the opted-in route,
Phoenix's span contains LiveLift's wrapper duration. The native root
LiveView span also reports its event and duration.

The [browser test](https://github.com/Manuel1471/LiveLift/blob/main/bench/e2e/event_telemetry.spec.mjs) held the counter
frame before delivery. The DOM count changed while the acknowledgment
sequence was still zero in Chromium, Firefox and WebKit. The probe
completed after the frame was forwarded and Phoenix acknowledged it.

## Decision

Use Phoenix's span as the server baseline and the existing LiveLift event
to investigate wrapper outcomes. Keep the browser probe in the benchmark
and document when each phase is observed. See the [telemetry guide](telemetry.md).
