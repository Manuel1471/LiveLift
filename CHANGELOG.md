# Changelog

## Unreleased

- Add an experimental `use LiveLift` / `@client true` path for simple native LiveComponents, with optimistic clicks, authoritative replies and reconnect snapshots.
- Support native `phx-change`, `phx-submit`, `phx-value-*` and flat event parameters in the marked handler subset.
- Bound pending native component actions and reject unsafe event parameter names before local execution.
- Compile flat event parameter patterns and a simple socket pipe without rewriting the LiveComponent handler.
- Add a Chromium benchmark comparing the same component with and without client prediction.
- Reject nested or duplicate native form names and unsupported control types instead of producing divergent client parameters.
- Deduplicate marked component events on the server before invoking the original handler.
- Add global and per-component switches that restore server-only rendering and events.
- Apply authoritative snapshots atomically and verify convergence across 1,000 reply orders and an interleaved server reset.
- Enforce matching list, map, node, and UTF-8 state-size limits in Elixir and the browser.
- Limit optimistic event parameters to 64 flat fields and 64 KiB on both sides before handler execution.
- Test duplicate replies and a connection cut while a prediction is pending.
- Compile chained `assign/update` operations in native marked handlers while preserving the original server body.
- Compile `String.contains?/2` for string and list patterns with seeded Elixir/JavaScript parity coverage.
- Match Elixir's Unicode whitespace semantics for compiled `String.trim/1`.
- Compile `String.length/1` with grapheme counting through `Intl.Segmenter` and test complex Unicode cases.
- Compile `Enum.take/2`, `Enum.drop/2`, and `Enum.uniq/1` with negative-count and structural-equality parity cases.
- Skip DOM reconciliation for structurally unchanged client and authoritative state, with a no-change list benchmark.
- Reuse keyed DOM rows on reorder when their rendered content depends only on the same immutable item; benchmark 1,000 rows in Chromium.
- Reject entity-obfuscated executable URL schemes and document the trust boundaries, XSS review, and remaining security gates.
- Validate the legacy demo's proposed client score and observed server revision before saving it.
- Add `mix live_lift.audit` to report client-compatible LiveComponent handlers and source-located blockers without changing app code.
- Emit server-side component event duration and outcome through `:telemetry`, without recording parameter or state values.
- Match Elixir's `if` without `else` semantics and reject malformed `if` branches with a clear compiler error.
- Fuzz 1,000 action expressions and syntax-check accepted generated JavaScript in Node.
- Render native HEEx expression attributes and conditional class lists on the client, preserving LiveView's initial class spacing and nil behavior.
- Add `mix live_lift.test` to compare a marked app handler against its generated Node action for supplied state and params.
- Run declarative parity cases for every opted-in app component in CI, rejecting missing marked events or modules.
- Queue new disconnected component actions for up to 30 seconds and replay them after a fresh LiveView snapshot, while dropping ambiguous in-flight events.
- Restore the authoritative snapshot and report a conflict if offline replay fails after reconnect.
- Run browser behavior, focus retention, and axe WCAG A/AA checks in Chromium, Firefox, and WebKit in CI.
- Replace dynamic text wrapper spans with text nodes bounded by comments, preserving native markup.
- Cover 1,000 generated action states and 1,000 template renders with seeded Elixir/JavaScript parity checks.
- Isolate the internal LiveView parser behind an adapter and add a non-blocking CI lane against LiveView `main`.
- Gate the planned LiveComponent API on a two-line migration spike and a real-browser convergence test.
- Match HTML attribute entities and native checkbox, select and textarea values across server and browser rendering.
- Document LiveView-shaped API feasibility spikes and formal client semantics.
- Exclude the release guide from Hex and run CI on Elixir 1.18/OTP 27 and Elixir 1.20/OTP 29.
- Keep server revision and server-owned values across island remounts and LiveView reconnects.
- Preserve focused controls while keyed rows move and isolate keys from sibling loops.
- Add real Chromium integration tests for client/server synchronization, editing and WCAG A/AA checks.
- Validate action rendering before committing the next client state.

## 0.1.0-rc.1 (prepared, not published)

- Initial experimental client templates, actions, keyed lists and app-defined components.
- Explicit LiveView event bridge with versioned server patches.
- Phoenix 1.8 installer, source maps, compatibility checks and benchmarks.
