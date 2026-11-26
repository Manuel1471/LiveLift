# Phase 7 — Consumer app with a custom LiveSocket

The integration script generates a fresh Phoenix 1.8.16 app and gives it
a hook factory, an app-owned hook and `/workbench` as its LiveSocket
path. The CLI installer reports the unsupported hook configuration.
The test compares `assets/js/app.js`, `mix.exs` and `.gitignore` byte for
byte and checks that neither generated JavaScript entry point exists.
A separate installer test checks the same behavior for a dynamic
`assets.deploy` alias with a standard hook map.

The fixture follows the [manual integration guide](../phoenix-integration.md#manual-asset-integration).
It adds the generation step to both Mix aliases and merges the LiveLift
hook into the factory result. Chromium, Firefox and WebKit check that the
app hook mounts over `/workbench/websocket` and stays active after a
LiveLift click and a server save. Both kill switches return the component
to standard LiveView behavior.

```sh
LIVE_LIFT_INTEGRATION_MANUAL=1 LIVE_LIFT_CONSUMER_BROWSER_PORT=4053 \
  sh test/integration/phoenix_consumer.sh
LIVE_LIFT_INTEGRATION_MANUAL=1 LIVE_LIFT_REGISTRY_VERSION=0.1.0-rc.1 \
  LIVE_LIFT_CONSUMER_BROWSER_PORT=4054 sh test/integration/phoenix_consumer.sh
```

The first command installs an unpacked local Hex package. The second
resolves the published Hex version directly. The compatibility workflow
runs the local package scenario on LiveView 1.2.15. The fixture exercises
Phoenix's esbuild pipeline and a custom socket. Other bundlers have
their own integration and deployment steps.

Both commands passed on macOS arm64 with Elixir 1.20.2 and OTP 29.0.3.
Each consumer passed migration, handler parity, `assets.build` and
`assets.deploy`. Chromium 158.0.8127.18, Firefox 159.0 and WebKit 27.2
saw the initial count of 3, a local change to 4 before acknowledgment,
and the server save `Saved 4`. Each browser observed the app-owned hook
and the custom WebSocket path.
