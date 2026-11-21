# Timer routing spike

A stateful LiveComponent shares the parent LiveView process. The
LiveComponent callback contract has no `handle_info/2`.

The integration probe schedules `Process.send_after(self(), message, 0)`
from a regular component event. The parent receives the message in
`handle_info/2` and updates the component via `send_update/2`. The
component's similarly named function never receives the message. In the
same fixture, `Phoenix.LiveView.send_update_after(socket.assigns.myself,
assigns, 0)` reaches the component through Phoenix's update path without a
parent message handler.

Run from `examples/demo/`:

```sh
mix test test/live_lift_demo_web/live/timer_routing_test.exs
```

The browser timer design needs to respect those two owners. A component
timer can target an update using the native component API. A process timer
is owned by a LiveView and needs a LiveView opt-in path for
`Process.send_after/3` and `handle_info/2`. A client prediction and its
authoritative server update must refer to the same timer. Verify one-shot
delivery, cancellation on removal, reconnect behavior and the server-only
path before marking timer support complete.
