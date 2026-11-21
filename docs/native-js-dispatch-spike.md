# Native LiveView dispatch spike

This experiment is for LiveLift maintainers working on delivery 5.3 in
the experimental release.

## Question

Can an island use Phoenix's `JS.dispatch` to notify app-owned JavaScript
on a local element without a second event system?

## Method

Run `npm run e2e -- native_dispatch_spike.spec.mjs` from `bench/`. Encode
a `workspace:preview` command with the installed Phoenix library. Inject
the binding into the native counter to exercise Phoenix separately from
LiveLift's compiler. Give the command an inner selector and set
`bubbles: false`. Install a handler on the target and witnesses on
the document and an element outside the source that matches the selector.

## Result

Chromium 158.0.8127.18, Firefox 159.0 and WebKit 27.2 all passed locally
on 2026-11-21 with LiveView 1.2.13 on macOS arm64, including a rerun
with `LIVE_LIFT_TEST_DEPLOY=1`. The target receives a `CustomEvent` with the native `dispatcher`. The
outside target and document bubble listener stay idle. The island's
action sequence and server revision stay at their initial values.

## Limits

The experiment uses the default selector. A non-bubbling DOM event can
still be observed by ancestor capture listeners. The test probes local
delivery. An app listener can run its own effects. The compiler must
still decide precisely which event names, options and payloads to admit.

## Decision

Use native `JS.dispatch` with explicit local options as the next candidate
for the 5.3 allowlist. Validate it as literal HEEx before enabling it.
