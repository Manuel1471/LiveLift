# Phase 7 — Missing browser APIs

## Question

What does the app do when a browser lacks an API used by the shared hook
or by a compiled grapheme operation?

## Method and result

A scratch Playwright probe removes one API before page scripts execute.
Without `Object.hasOwn`, the opted-in counter fails to acknowledge the
click and its snapshot remains at zero. Without `Intl.Segmenter`, the
native form mounts, but filling the note raises the explicit grapheme
error and leaves the acknowledgment at zero.

The first server-only run exposed a separate compatibility bug. Phoenix
includes the native form's `_target` as a path list. The LiveLift
parameter validator rejected it even with LiveLift disabled. LiveLift
now counts the bounded native target as text for validation and passes
the original params through to the handler. Sequenced payloads still
use the existing parameter shape and limits.

The repeatable checks cover two working configurations. The opted-in
counter confirms a click with `Intl.Segmenter` removed. With LiveLift
disabled on the server and both APIs removed, the same Phoenix form
rejects two graphemes, accepts three, and persists the Unicode value
through its original LiveView handler. The asset bundle still loads in
that configuration and the test observes no browser errors. Another
test holds the form view chunk, verifies that the native change reaches
Phoenix before client mount, then checks that the loaded view displays
the resulting validation message.

```sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/browser_capabilities.spec.mjs
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_DEMO_SERVER_ONLY=1 npm run e2e -- \
  e2e/browser_capabilities.spec.mjs
```

Against baseline `d99bd9a`, all 36 selected deployed checks passed in
Chromium 158.0.8127.18, Firefox 159.0 and WebKit 27.2. Six capability
checks passed with development assets. The three server-only checks
passed with each parser. The 169 library tests passed per parser
configuration on LiveView 1.2.15, and 37 component tests passed in a
checkout pinned to 1.2.0. The shared hook measured 8,192 gzip bytes.
The packaged consumer with a custom LiveSocket passed both asset builds
and the browser checks for prediction, saving and the two kill switches.

## Limits and decision

Use the existing server-only switch where the app needs to serve
clients that lack required APIs. CI is configured to verify both
configurations with deployed assets. The checks remove individual capabilities from current
engines. Running the complete site against historical browser binaries
would also exercise their syntax support, Unicode versions and Phoenix's
own runtime. See the [published API requirements](../production-readiness.md#browser-requirements).
