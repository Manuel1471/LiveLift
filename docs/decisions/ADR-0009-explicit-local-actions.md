# ADR 0009 — Mark actions that need no LiveView round trip

Accepted 2026-11-22 for the experimental native API.

Use `@client :local` on a supported synchronous `handle_event/3` for transient
display state. Preserving native event bindings and the original Elixir
handler keeps server rendering, disabled-mode behavior, and parity checks
available. Inferring local-only behavior from an assign name or function body
would make a small handler edit change whether the browser sends the event.

Keep local edits in memory for the mounted instance. The browser validates
the complete local result against the normal state limits and overlays the
fields written by that action when rendering. The optimistic replay queue
works from the server snapshot. Compile-time checks reject local writes that
overlap with optimistic handler and timer reads or writes. A server save
receives explicit event parameters under the normal Phoenix trust model.

The [browser acceptance case](https://github.com/Manuel1471/LiveLift/blob/main/bench/e2e/local_actions.spec.mjs) checks
the outbound event trace, focus, and rendering after optimistic and server
updates. It checks a full reload, a disconnected click, and all three browser engines.
The [native guide](../native-livecomponent.md#local-actions) covers semantics
before mount and on a new instance. Revisit the storage model if app pilots
need local values to outlive the island.
