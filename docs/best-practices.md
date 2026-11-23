# Adopt LiveLift in small steps

## Pick an interaction with a clear owner

Start with one frequent interaction in a small LiveView or stateful
LiveComponent. Good first candidates include reordering a visible list,
toggling a preview, and updating a counter. Use:

- `@client :local` for disposable display state such as preview order or a
  filter. The browser keeps the edits while the island remains mounted.
- `@client true` when immediate feedback helps and the server must confirm
  the result. Every optimistic interaction still sends a LiveView event.
- An unmarked handler for writes to the database, authorization, external
  calls, and other side effects. Show a success message after the server
  confirms the operation.

Run `mix live_lift.audit --path lib/my_app_web` to find compatible handlers.
If a view's render uses HEEx outside the compiler subset, opt in a smaller
stateful component. Keep routing, uploads, streams, and permission checks
in LiveView. See the [Phoenix adoption guide](phoenix-integration.md#adopt-livelift-in-an-existing-phoenix-app).

## Keep the browser projection small

Pass only fields the visible region needs. A browser can inspect the initial
assigns and generated actions, so exclude secrets and server-only records.
Initialize the fields on the server and prefer simple lists, maps and
scalars. Use a durable unique ID per row, such as `id={row.id}` with
`:key={row.id}`, so the browser can retain the focused input during reorder.

Keep local display assigns separate from shared state. To persist a choice,
submit explicit values such as a row ID, then look it up and authorize the
operation on the server. Account for repeated submissions at the persistence
layer when a write needs idempotency. See the [state contract](sync.md) and
[security model](security.md).

## Test the interaction in both runtimes

Add a parity case per marked handler with typical and boundary inputs, then
run `mix live_lift.test --cases test/live_lift_cases.json` with Node available
on your CI runner. Use browser tests
to exercise keyboard focus, form changes, and a server update during the
interaction. For an optimistic action, include a test in which the server
corrects a prediction or the connection is interrupted. Run
`mix assets.deploy` in the deployment build to check the production bundle.
See the [parity guide](native-livecomponent.md#verify-parity).

## Measure the user-visible change

Compare the same interaction on the same app with and without the marker.
Record time to visible feedback, time to server confirmation, WebSocket
event volume, and the initial JavaScript size for that page. Use a
representative data set and include a device or CPU profile that reflects
your users. A local action can eliminate its event. An optimistic action
still uses the server and is most valuable when the earlier visual
response improves the interaction. See the [event telemetry guide](telemetry.md)
and [production limits](production-readiness.md).
