# Phase 7 — Enforced script CSP

The demo route `/local-actions-csp` serves the same LiveView under an
enforced `Content-Security-Policy` response header set by Phoenix. Scripts
come from the app's origin, and the policy also allows the app's
LiveView WebSocket.
The policy omits `unsafe-inline` and `unsafe-eval`.

The test checks that the split view chunk loads, the local preview
reverses the rows, the optimistic increment receives its server
acknowledgment, and the server-only event saves the right row. It
expects zero policy violations from those operations. As a control,
it inserts a harmless inline script and checks that the browser
reports exactly one violation and never runs the script.

## Internal source review

The two `innerHTML` assignments are in
[`client_hook.js`](../../assets/js/live_lift/client_hook.js).
The entity decoder receives compiled text and static attribute literals.
The other assignment initializes the legacy string template registered by
the application. Native state bindings instead use text node creation,
`textContent`, and allowed attribute operations. The server passes
validated parameters to the original application handler, which uses
the server's socket state. The relevant template, state and parameter
regression tests ran alongside the browser checks.

## Reproduce

```sh
mix test test/live_lift/{component,template,compiler_fuzz,view}_test.exs
cd assets && npm test
cd ../bench
npm run e2e -- e2e/content_security_policy.spec.mjs
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/content_security_policy.spec.mjs
```

On 2026-11-24, both asset modes passed in Chromium 158.0.8127.18,
Firefox 159.0, and WebKit 27.2. The baseline was `da2835f` on macOS 26.5.2
(Apple M4), Elixir 1.20.2, OTP 29, Node 26.5.0, and Playwright 1.65.0.
The deployed build uses digested assets. The focused Elixir suite passed
68 tests, and the JavaScript runtime passed 34. Style policies, Trusted
Types, and an independent review remain outside this test.

A later clean-checkout run found a Firefox timeout while Playwright
intercepted and re-fetched the document. The route now sets the header
in Phoenix. Three repetitions per browser passed in each asset mode
after this change, for 18 checks.
