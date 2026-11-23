# How state and events move

A LiveLift island is the region inside an opted-in LiveView or
LiveComponent. Phoenix renders the initial HTML and supplies the initial
assigns used by that region. After the hook mounts, LiveLift reconciles
the island's children. Phoenix continues to own the rest of the page.

## Choose the event mode

| Handler | What the user sees | Who owns the result |
| --- | --- | --- |
| Unmarked | LiveView sends the event and renders the server result. | The server owns decisions, permissions and persisted data. |
| `@client true` | The hook applies a prediction immediately. LiveView receives the event and confirms or corrects it. | The server owns the confirmed assigns. |
| `@client :local` | The mounted hook changes display assigns immediately, with zero LiveView events. | The browser owns those edits for the life of the island. A fresh mount uses server defaults. |

## Follow an optimistic click

1. A click on `phx-click="inc"` reaches the mounted hook. LiveLift runs the
   generated action on its current projection of assigns and updates the
   visible count.
2. The hook sends the event name, explicit parameters, and an action
   sequence through LiveView. Phoenix runs the original `handle_event/3`
   against the server's socket assigns.
3. The response identifies the acknowledged sequence and supplies a server
   snapshot. LiveLift applies the snapshot and reapplies pending predictions
   in order. If the server count changed independently, the visible value
   converges to the server's result once the pending events settle.

For example, the browser may show 6 immediately after incrementing a count
last seen as 5. If another server event has already advanced the count to 7,
the server applies the increment to 7 and confirms 8. The browser displays 8
after reconciliation.

LiveLift manages the revision and sequence. Keep your usual `phx-*` event
bindings and handle the application parameters as usual. After reconnect,
the hook uses a server snapshot to recover pending optimistic actions.
The offline queue is bounded and lives in memory. Treat confirmed
persistence as an explicit server operation. See the
[reconnect options](native-livecomponent.md#reconnect-and-offline-actions).

## Combine local preview with a server save

A local sort can update a `:preview_rows` assign. Keep fields written by
that action separate from fields read or written by optimistic handlers and
their timers. If the user chooses a row to save, pass its ID through
`phx-value-id` on an unmarked event. The server verifies the selection and
can update a separate `:saved_row` assign. The user's preview order remains
visible on the same island.

The [native component guide](native-livecomponent.md#local-actions) covers
behavior during loading and remounts. The [adoption practices](best-practices.md)
show how to choose the right boundary for an existing page. See the complete
[sort and save demo](https://github.com/Manuel1471/LiveLift/blob/main/examples/demo/lib/live_lift_demo_web/live/local_actions_live.ex).
