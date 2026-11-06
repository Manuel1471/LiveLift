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

## Decision

## S4 — migration surface

**Passed in the executable spike.** Two copies of a normal LiveComponent use
identical `~H` and `handle_event/3` source. The opt-in copy changes its `use`
line and adds `@client true` above the handler. Both compile and render the
same button and count; the opt-in copy gains the generated DOM boundary.
CI now runs the spike on the supported toolchains and in the optional LiveView
`main` lane.

## S5 — browser acceptance gate

**Pending.** S1–S4 do not execute that handler in the browser. Before shipping
`use LiveLift`, a real mounted LiveComponent must run the marked handler
optimistically, send the normal LiveView event, receive an authoritative
response and converge after reconnect. Its source diff must remain only the
`use` line and `@client true`; no template or handler rewrite is acceptable.

## Decision

Proceed with a narrow `use LiveLift` implementation behind this browser gate.
Keep the current `client_template` API working. Do not claim the target API
is production-ready from compile-time spikes alone.
