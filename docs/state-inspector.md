# Development state inspector

For app developers using experimental LiveLift.

In the demo, build development assets and open
`/native-counter?live_lift_inspect=1`. Click **Add one** a few times, then
choose **Inspect LiveLift state**. Select an island and step through its earlier
snapshots. **Follow live** jumps to the latest value and follows new changes.
The rest of the page continues to receive updates. The history viewer does
not replay events or change the live island.

The inspector records distinct state snapshots, including optimistic updates
and server corrections. It keeps up to 64 snapshots across all currently
mounted islands. A snapshot larger than 65,536 UTF-16 code units is shown as
an omission. Island removal clears its history and reloading clears all
history. Snapshots stay in memory on the current page.

## Use with esbuild in an installed app

Keep the usual LiveSocket configuration and guard the LiveLift hook with a
build-time flag. The default Phoenix esbuild profile places `deps` on
`NODE_PATH`, which makes the packaged inspector available to this example.

```javascript
// Replace only the LiveLift entry in the existing LiveSocket hooks map.
LiveLift: LIVE_LIFT_INSPECT && new URLSearchParams(window.location.search).get("live_lift_inspect") === "1"
  ? require("live_lift/assets/js/live_lift/devtools.js").withStateInspector(createClientHook(liveLiftViews), document)
  : createClientHook(liveLiftViews),
```

Add `--define:LIVE_LIFT_INSPECT=false` to the default esbuild profile. Append
`--define:LIVE_LIFT_INSPECT=true` to the development invocation and watcher
only. Keep the deployment invocation on the default false definition.
The [demo entry point](https://github.com/Manuel1471/LiveLift/blob/main/examples/demo/assets/js/app.js) imports the same
module using a checkout-relative path. The deployed inspector test checks
the digested JavaScript and verifies that the development query has no
effect on the deployed page.

The inspector displays each island's browser-visible state. Keep the
normal LiveLift rule of excluding secrets from that state.
