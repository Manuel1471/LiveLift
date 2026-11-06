# LiveView state contract

Each island has a single owner for every top-level state field. Fields listed in
`server_fields` belong to LiveView; every other field belongs to the browser.

```heex
<LiveLift.View.island
  id="score"
  module={MyApp.ScoreView}
  state={%{count: 0, saved_count: nil}}
  server_fields={[:saved_count]}
  server_revision={@score_revision}
/>
```

`defclient` actions may omit server fields. LiveLift carries their latest values
forward. An action that changes a server field fails before rendering. `$server`
submits only client-owned fields as `%{"state" => ..., "revision" => ...}`.
Handle the event in the parent LiveView and send a response:

```elixir
def handle_event("save", %{"state" => %{"count" => count}}, socket) do
  revision = socket.assigns.score_revision + 1
  socket = assign(socket, score_revision: revision, saved_count: count)
  {:noreply, LiveLift.Sync.push(socket, "score", revision, %{saved_count: count})}
end
```

Keep the revision in the LiveView socket and increment it for every patch to
the same island. The browser ignores a duplicate or older revision, validates
the patch, and merges only declared server fields. LiveView's own assigns and
HTML outside the island can update at the same time. `phx-update="ignore"`
keeps LiveView from replacing locally edited DOM.

Pass current server-owned values in `state` and the current revision in
`server_revision` on every render. On remount, the browser starts from that
snapshot instead of revision zero. When LiveView updates the island's `data-*`
attributes after reconnect, the hook applies newer server-owned values while
retaining client-owned fields. A missed event cannot silently roll back a
newer server revision.

This is an explicit event protocol, not automatic shared state. Each server
event must validate its input and decide how to handle stale submitted data.
The `revision` in a submitted event is the last server revision observed by
that browser; use it for optimistic concurrency checks when writes can race.
On a full remount, initialize the island from the current server state.
