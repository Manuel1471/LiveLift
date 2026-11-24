# Phase 7 — Emergency switch in a real browser

On 2026-11-24, the switch checks ran on macOS 26.5.2 (Apple M4), Elixir
1.20.2, OTP 29, Node 26.5.0, Playwright 1.65.0, and Phoenix generator
1.8.16. The library baseline was `54a46df`. The browser harness serves
the output of `mix assets.deploy` with watchers disabled.

```sh
LIVE_LIFT_CONSUMER_BROWSER_PORT=4050 sh test/integration/phoenix_consumer.sh
mix test test/live_lift/component_test.exs
```

The consumer passed both switch modes on Chromium 158.0.8127.18, Firefox
159.0, and WebKit 27.2. In each browser the probe:

1. Waits for an opted-in counter to initialize and its LiveView to join.
2. Applies the global or per-component switch through a controller that
   exists only in the temporary browser test app.
3. Fetches a fresh response and verifies that the LiveLift hook is absent.
4. Clicks the marked button in the open page and observes a full reload.
5. Verifies the reloaded view has no LiveLift acknowledgment attribute and
   a subsequent click updates the counter through LiveView.

The 31 component tests also passed. They confirm the authoritative
handler runs before the disabled reply and supplies the updated socket.
The test counter reinitializes on navigation because its count is held in
the socket. Applications that need durable values should persist them
in their server workflow.

The browser probe also passed with `LIVE_LIFT_LIVE_VIEW_VERSION='== 1.2.0'`
on port 4052, and with `LIVE_LIFT_INTEGRATION_IGNITER=1` on port 4051.
The Igniter run also exercised split assets with a local test package.
