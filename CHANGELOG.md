# Changelog

## Unreleased

- Restore opted-in text field drafts after reload and submit them through the existing LiveView form.

- Send app-owned DOM events with literal native Phoenix `JS.dispatch` bindings inside an island.

- Preserve supported Phoenix class commands across LiveLift updates on the same DOM node.

- Compile validity and field reads from schemaless Ecto string changesets with required, grapheme length, and bounded format validation.
- Restore acknowledged timers when reconnecting to the same instance with an older DOM snapshot.
- Compile native LiveView mailbox timers and replay their `handle_info/2` effects in order with pending actions.
- Reuse native optimistic event reconciliation for opted-in root LiveViews, including authoritative mailbox and URL parameter updates.
- Predict bounded native LiveComponent timers in the browser and reconcile their one-shot updates with Phoenix's `send_update_after/3`.
- Reconcile server updates to native LiveComponents without advancing the browser's action sequence, including Phoenix `send_update_after/3`.
- Support per-island view chunks with an opt-in split registry and preserve native events during loading.

- Batch authoritative renders by animation frame while keeping local predictions immediate.

- Preserve static and unchanged template subtrees during state changes.

- Track keyed row dependencies across authoritative snapshots and reuse rows whose rendered values are unchanged.

- Move unchanged keyed rows directly during reconciliation without allocating temporary elements.

- Resume unacknowledged actions on the same component instance and configure how offline actions resolve across remounts.

- Recover optimistic actions delivered out of order and suppress duplicate execution.

- Normalize JavaScript negative zero for integer operations while preserving signed floats.

- Normalize pipes and conditional expressions before JavaScript emission.

- Compile exact deletion and positional insertion, replacement, and deletion for lists.

- Compile map projection counts and explicitly sorted atom key names with Elixir parity.

- Compile `String.replace/3,4` with Elixir pattern, grapheme, callback iodata, and `global` semantics; verify seeded parity and native browser behavior.
- Compile `String.split/1,2,3` with Elixir whitespace, grapheme, pattern-list, trim, and parts semantics, backed by a Unicode spike, seeded parity, and native browser coverage.
- Compile `String.downcase/1` with Elixir's context-free Unicode mapping, a full scalar parity spike, seeded strings, and three-browser native coverage.
- Compile the callback form of `Enum.with_index/2` with zero-based indexes and parity; reject tuple-producing forms with a source-located alternative.
- Compile `Enum.flat_map/2` for list-returning anonymous callbacks, with bounded output, seeded parity, invalid-result rejection, and native browser coverage.
- Compile `Enum.join/1,2` with Elixir string conversion for safe state values and chardata, plus invalid-value rejection, float text parity, and native browser coverage.
- Compile `Enum.count/1,2` for lists and Elixir-truthy predicates, with seeded parity and native browser coverage.
- Compile `Enum.sort_by/2` with stable Elixir term order for safe state values, including Unicode and tagged floats; verify seeded parity and native keyed focus in three browsers.
- Compile `Enum.reduce/2,3` for lists and two-argument anonymous callbacks, with empty-list behavior, seeded parity, and native browser coverage.
- Compile `Enum.find/2,3` for list inputs and one-argument anonymous predicates, with seeded Elixir/JavaScript parity and rejection of unsupported callback shapes.
- Compile expression pipes into supported calls and same-component helpers, with seeded parity, source-located invalid-target rejection, and three-browser native coverage.
- Compile same-component multi-clause `defp` calls in marked handlers, including later definitions and calls between helpers, through bounded case matching; reject guards and recursion with source locations.
- Compile bounded `case` patterns for marked handlers, with type-strict float and signed-zero matching, list and partial-map bindings, seeded parity, source-located guard errors, and three-browser convergence.
- Compile `cond` clauses with Elixir truthiness, lazy branch selection, and an explicit no-match error; include it in the seeded parity corpus.
- Compile finite Elixir float literals and mixed arithmetic using a tagged browser value that preserves `1.0`, negative zero, and server display; verify 5,000 seeded bit patterns and native handler parity.
- Decide the float wire and parity model before enabling decimal literal compilation; document the type-loss spike and acceptance gate.
- Compile native `assign_new/3` with a zero-argument callback, optional initial fields, lazy fallback, and Elixir/JavaScript plus browser parity.
- Record the bounded native handler matrix and test 18 source-located rejections for forms outside the published client language.
- Delay native `phx-change` prediction and delivery for numeric or `blur` `phx-debounce` on inputs and textareas; verify timing in three browsers.
- Expand one default slot in local native function components while preserving the caller's assigns; reject named or repeated slots explicitly.
- Compile local app-defined `~H` function components with explicit props into native client templates, including parent-owned events; reject remote components with source-located errors.
- Add app-owned `move_to_top` list ordering with parity cases and keyed focus preservation in three browsers.
- Add live validation for a nested native form field, with an immediate accessible error, server-side save rule, Elixir/JavaScript parity cases, and three-browser tests.
- Verify the local installer, `$server` migration boundary, server-authoritative save, parity task, and both asset aliases in a fresh Phoenix consumer app.
- Show a server-authoritative save after an optimistic native action in the demo, tested in both component modes across three browsers.
- Document why legacy `$server` cannot be replaced by `phx-click` alone and give a source-located migration error and manual guide.
- Migrate bounded nested legacy `$submit` form names when `event.params` reads the matching nested path; reject mismatched paths before writing.
- Support bounded nested map names in native marked forms, with matching Elixir/browser validation and nested handler reads.
- Migrate flat legacy `$submit` forms using `event.params.field` to native `phx-submit` handlers, rejecting mismatched event access.
- Migrate legacy select `$change` and textarea `$input` actions to native `phx-change`, preserving selected bindings and checking Elixir/Node results.
- Migrate legacy text `$input` actions using `event.value` to native `phx-change` with flat `params["value"]`, with Elixir/Node parity coverage.
- Add a bounded HEEx template parser fallback when LiveView's private parser is unavailable or changes its result shape; compare its nodes against the current parser on demo templates.
- Report an actionable source-located error when a LiveView upgrade removes or changes the private HEEx parser contract.
- Make the Phoenix asset installer repair partially wired aliases and reject an unsupported hook layout before changing any files.
- Migrate legacy actions that update multiple map fields while preserving reads from the original state; verify generated handlers against Elixir and Node.
- Add `mix live_lift.migrate` for simple legacy click views. It generates a separate native LiveComponent, validates the converted handler, and rejects unsupported legacy forms with a source location.
- Warn when compiling the legacy `LiveLift.Client` or `LiveLift.View.island/1` API; point users to the native LiveComponent migration guide. Existing code still runs.
- Support flat native `phx-change` forms by suppressing the duplicate browser change event before LiveView handles it.
- Benchmark 1,000 native LiveComponent rows in Chromium and bound the demo's row count for reproducible performance checks.
- Add an editable native HEEx list with per-row `phx-submit` forms and Elixir/JavaScript handler parity.
- Support dynamic native `phx-value-*` expressions so app-owned lists can remove rows by item ID, and keep server delivery when the clicked control disappears optimistically.
- Compile `Integer.to_string/1` for safe integers to build stable item IDs in marked handlers.
- Compile `Map.take/2` for a literal atom-key list with seeded Elixir/JavaScript parity cases.
- Use a native HEEx repeated element's `id={item.id}` as its client list key and preserve focused server-rendered rows across reorder.
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
- Exercise 100 independent LiveLift components per page in three browsers and benchmark navigation and mount against server-only components.
- Compile shallow `Map.merge/2` and atom-keyed `Map.delete/2` with seeded Elixir/JavaScript parity coverage.
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

### Added

- Use native LiveView focus commands in literal `phx-click` bindings inside an island.
- Preserve Phoenix's used-field markers for optimistic changeset forms.
- Read displayed values, field usage, and error messages from native changeset forms in marked handlers.

## 0.1.0-rc.1 (prepared, not published)

- Initial experimental client templates, actions, keyed lists and app-defined components.
- Explicit LiveView event bridge with versioned server patches.
- Phoenix 1.8 installer, source maps, compatibility checks and benchmarks.
