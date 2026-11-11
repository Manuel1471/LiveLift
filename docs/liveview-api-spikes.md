# LiveView-shaped API spikes

Run `mix run spikes/liveview_api.exs` against each supported LiveView version.
The spike passes on Elixir 1.20.2 / OTP 29 / LiveView 1.2.13.

## S1 — `@client true` and `~H` source

**Feasible at compile time.** `@on_definition` sees the unexpanded
`{:sigil_H, ...}` AST from `render/1` and the marker on a following
`handle_event/3` clause. The marker must be consumed after that clause;
otherwise it silently marks subsequent handlers. The prototype verifies only
one clause is marked. A render body that delegates to another function does
not contain a literal `~H`; the future API must reject it with a source-line
error or use an explicit marker.

## S2 — automatic DOM boundary

**Feasible for a simple LiveComponent render.** `defoverridable render: 1`
allows a wrapper to call the original `render/1` via `super/1` and surround its
real `~H` result with `phx-hook` and `phx-update="ignore"`. No user template
change is needed in the prototype. Elixir macro hygiene requires
`var!(assigns)` in the generated wrapper. This does not yet prove lifecycle
behavior under nested components, slots, streams or navigation; those need
real LiveView integration tests before shipping the API.

## S3 — authoritative handler response

**Feasible to intercept marked clauses through public mechanisms.** A
`defoverridable handle_event: 3` wrapper calls the original clauses with
`super/3`. The prototype intercepts only the marked event and leaves an
unmarked event untouched. `Phoenix.LiveView.push_event/3` queues a response
on a LiveView socket. The spike does not implement server/client state
reconciliation. Before adding the API, prove that a mounted LiveComponent can
emit the patch from a real event and define how pending predictions are
replayed or rejected.

The subsequent native implementation now returns versioned authoritative
snapshots through LiveView event replies, replays pending actions, and rejects
duplicate event sequences before invoking the original handler. This is
covered by the runtime, component, and Chromium tests.

## S4 — migration surface

**Passed in the executable spike.** Two copies of a normal LiveComponent use
identical `~H` and `handle_event/3` source. The opt-in copy changes its `use`
line and adds `@client true` above the handler. Both compile and render the
same button and count; the opt-in copy gains the generated DOM boundary.
CI now runs the spike on the supported toolchains and in the optional LiveView
`main` lane.

## S5 — browser acceptance gate

**Passed for the narrow native component surface.** The Chromium acceptance
tests mount the same `Phoenix.LiveComponent` with and without opt-in. The
client version runs its marked `handle_event/3` optimistically, sends the
normal LiveView event, and converges to the authoritative server reply. Tests
also cover two pending clicks, a server reset between predictions, a
reconnect, and a connection cut with a pending prediction. The source diff is
the `use LiveLift` line and `@client true`; `~H`, `phx-*`, and the original
handler body remain unchanged. See `bench/e2e/live_lift.spec.mjs`.

This pass does not validate arbitrary LiveComponents. The compiler currently
supports only the documented subset of handlers and templates; nested
components, slots, streams, and richer forms still need separate gates.
The later flat-form spike now passes in Chromium, Firefox, and WebKit: a
per-row `phx-change`/`phx-submit` form edits an item through the original
`handle_event/3`, and the hook suppresses the browser's duplicate `change`
event before LiveView sends a second request. This validates flat text
parameters and a keyed list; it does not validate arbitrary LiveView forms.

## Decision

Proceed with the narrow `use LiveLift` implementation. Keep the current
`client_template` API working. Treat the browser gate as evidence for the
supported subset, not as a production-readiness claim for all LiveView code.
