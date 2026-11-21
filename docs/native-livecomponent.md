# Opt in a LiveComponent

For a full workflow, see the [verified migration diff](liveview-migration-diff.md)
from audit through CI and asset generation.

The experimental component path keeps the original LiveView render and event
handler. Start with a normal stateful component:

```elixir
defmodule MyAppWeb.Counter do
  use Phoenix.LiveComponent

  def render(assigns) do
    ~H"""
    <button phx-click="inc" phx-target={@myself}>{@count}</button>
    """
  end

  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end
end
```

Add only `use LiveLift` and mark the handler:

```diff
   use Phoenix.LiveComponent
+  use LiveLift

+  @client true
   def handle_event("inc", _params, socket) do
```

`~H`, `phx-click`, `phx-target` and the handler body remain the same. LiveLift
wraps the original server render in an owned DOM boundary. On a marked click,
the hook runs the compiled handler locally and sends the event through
LiveView's public `pushEventTo` API. The server executes the original handler
on its own socket and replies with its authoritative assigns. Unmarked
handlers continue through LiveView normally. After reconnect, the browser
reconciles its predictions with the server snapshot.

After mount, changes to client-rendered fields from `update/2` or
`update_many/1` also reach the browser as authoritative snapshots. For example,
an unmarked handler can call
`Phoenix.LiveView.send_update_after(socket.assigns.myself, [label: "Ready"], 50)`.
This uses Phoenix's server timer and leaves the browser's action sequence intact.

For a browser prediction, mark a handler that schedules a literal assign
patch on its own component:

```elixir
@client true
def handle_event("show_hint", _params, socket) do
  Phoenix.LiveView.send_update_after(socket.assigns.myself, [hint: "Saved"], 100)
  {:noreply, socket}
end
```

The browser starts the delay when it handles the click. Phoenix schedules the
authoritative update when it receives the action. Acknowledging the action
keeps the existing prediction; the server's final snapshot settles the
timer. Duplicate deliveries of the same sequenced action keep one server
timer. The client cancels its timers when the hook is destroyed or
disconnected. Reconnection uses the new server snapshot and the normal
action replay policy. When the same instance's DOM snapshot trails a newer
server reply, the browser resumes the acknowledged timers from that reply
without resending their scheduling events.

Use a plain params argument, a literal delay from 0 to 60,000 milliseconds,
and a keyword list with one to eight distinct literal scalar values for
client fields. The component uses Phoenix's default update callback. LiveLift
admits up to 32 pending timers per instance; further schedules are acknowledged
without adding a timer until a slot frees up. Keep computed patches, other
targets, or custom updates in unmarked server handlers.

Check a marked handler against the generated JavaScript from your Phoenix app:

```sh
mix live_lift.test MyAppWeb.Counter --event inc --state '{"count":0}'
mix live_lift.test MyAppWeb.Form --event draft \
  --state '{"draft":null}' --params '{"value":"Hi"}'
mix live_lift.test --cases test/live_lift_cases.json
```

The task runs the original server handler and the generated action with
the supplied state and parameters. Parameters can be strings or bounded
nested maps. The task compares the exact JSON types of their client fields.
For a supported timer it also checks the authoritative queued delivery
against the generated timer result, without waiting for the delay. A cases file is a JSON array such as:

```json
[
  {"module":"MyAppWeb.Counter","event":"inc","state":{"count":0}},
  {"module":"MyAppWeb.Counter","event":"inc","state":{"count":9007199254740990}}
]
```

For each listed LiveView and LiveComponent, the task requires a case for
every marked event. It also fails if the app contains an opted-in module
omitted from the file.
Run it in CI with representative and boundary cases. A finite corpus cannot
prove parity for every input or replace browser tests.

This path accepts a literal `~H` render. For synchronous updates, write a marked
`handle_event/3` whose body returns `{:noreply, socket}` after one or more
`assign/3` or `update/3` operations. The expression must fit the
[client language subset](language.md). Marked handlers can read string
keys with `params["name"]`, `Map.get(params, "name")`, or nested paths such as
`params["profile"]["note"]`. They may call local `defp` functions with several
unguarded clauses, even when defined below the handler. For example,
`assign(socket, :label, label(socket.assigns.count))` can call
`defp label(0), do: "Empty"` and `defp label(count), do: Integer.to_string(count)`.
Recursion and guards remain on the server. The template supports
static `phx-click`, `phx-change`, `phx-submit`, `phx-value-*`, and
`phx-target={@myself}`. Native expression attributes `class={@tone}`,
`title={@title}`, `aria-label={@label}`, `value={@value}`, and `id={item.id}` are supported.
For a native `:for={item <- @items}`, put a stable `id={item.id}` on the repeated
element. LiveLift uses that ordinary HTML ID as its client key; it preserves
the server-rendered row and its focused input when an unchanged item moves.
The demo's `move_to_top` handler is app code built from `Enum.filter/2`,
`Enum.reject/2`, and `++`; repeated moves can produce any row order. It keeps
the focused input node when that row moves.
Local presentation function components are accepted when they return a literal
`~H` template and receive explicit props. They use ordinary `attr` declarations.
For example, the demo defines `<.move_button row_id={item.id} myself={@myself} />`
inside a keyed row; the button's `phx-click` still invokes the parent's marked
handler. A local component may use a prop in `:if`, text, or supported
attributes. Call-site directives, remote function components, and
multiple function clauses fail at compilation with a source location. Use an
Elixir expression such as `label={"A & B"}` for a prop containing an encoded
HTML entity; encoded static prop strings are rejected to avoid double escaping.
The default slot works through `{render_slot(@inner_block)}` once per local
function component. The demo's `<.feedback>` wraps its validation message this
way. Slot content keeps the caller's assigns and may contain other local
components. Named slots and repeated rendering of the default slot remain
server only.
Missing, duplicate, or invalid IDs fail instead of falling back to index keys.
`class={["base", @active && "active"]}` also works, including `false` and
`nil` values. Dynamic URLs and other expression attributes remain server only.
A handler may bind params with
`%{"name" => name}` or `%{"profile" => %{"note" => note}}` and chain `socket |> assign(...) |> update(...)` operations.
Direct nested `assign/update` calls are also accepted. Other LiveView features remain
server only. Unsupported
forms fail during compilation with a source location and a suggestion to keep
that handler on the server.
`assign_new(socket, :draft, fn -> socket.assigns.prefix <> " draft" end)` also
works in a marked handler. A field absent on the first render is omitted from
the client snapshot, then added by the click; an existing field is kept, even
when its value is `nil`. The demo shows this at `/native-optional`. The callback
must take no arguments and use the supported client expression subset.
Marked forms accept unique, safe map names such as `profile[note]`, with at most
four segments. Arrays (`items[]`), conflicting names (`profile` alongside
`profile[note]`), dynamic names, checkbox, radio and file
change events remain server only until their value semantics are covered.
For a marked `phx-change`, put `phx-debounce="300"` on its input or textarea
to delay both prediction and server delivery by 300 ms after the latest input.
`phx-debounce="blur"` waits until the control loses focus; an empty value uses
LiveView's 300 ms default. Blurring a timed control sends its latest value
immediately. Submitting its form cancels a pending change and sends the submit
with current form values. Other debounce values and placements fail at compile
time with a source location.
The demo's native form uses `phx-change="validate"` and `phx-submit="save"` on
the same form. Both handlers read `params["profile"]["note"]`; the change
handler shows a local error immediately and the save handler enforces the same
three-grapheme minimum on the server. The browser keeps the input value and
reconciles with the authoritative reply.
The browser shares a 100-action limit between sent and offline actions.
Offline actions created during a disconnect expire after 30 seconds.

On reconnect, the same mounted component resumes from its acknowledged
sequence. The browser retries outstanding actions with their original
sequences. The server acknowledges the contiguous sequence it has applied
and returns the current snapshot for duplicates. If a replay cannot apply
to the same server instance and an outstanding sequence may already have
been sent, reload the page before sending further marked actions.

If LiveView mounts a fresh component, LiveLift adopts that instance's
state. Unconfirmed actions sent to the previous instance are discarded.
By default, fresh offline actions that were never sent are replayed against
the new snapshot. Apps can discard those as well by setting:

```elixir
config :live_lift, reconnect_conflict: :discard
```

The default is `:replay_offline`. The queue survives a transport
disconnect while the hook stays mounted. Reloading the page clears it.
Optimistic events accept at most 64 string leaf parameters, nested to four
segments, and 64 KiB of
combined UTF-8 key/value content. The browser checks before predicting; the
server checks before invoking the marked handler. State limits are documented
in [the language contract](language.md).
The client combines authoritative snapshots that arrive within one animation
frame and renders the newest one. Local predictions remain immediate.
Sequence recovery does not wait for the next frame.

The client applies a newer snapshot, replays unacknowledged actions and commits
the result only after rendering succeeds. Stale replies can acknowledge
pending actions without rolling back a newer server revision. The convergence
suite runs 1,000 seeded reply orders with deliberate server corrections.
Duplicate replies do not run the handler again. A connection cut drops
in-flight predictions when the fresh LiveView snapshot arrives, then replays
only actions created while disconnected. Expired actions roll back to the
snapshot. If replay against the new server state fails, LiveLift restores the
snapshot, drops the queue, and raises an explicit conflict error. The queue is
not durable across a page reload or a remount.

To turn off prediction without editing components, configure either switch:

```elixir
config :live_lift, enabled: false
config :live_lift, disabled_components: [MyAppWeb.Counter]
```

New renders use the original LiveView
markup and event path. An already mounted client reloads on its next marked
event when the server reports that the switch is off; reload active pages to
apply the switch immediately.

The demo route `/native-list` reverses a native HEEx list while keeping a focused
row in place. It adds and removes rows with `phx-value-id={item.id}`, and saves
each row's label with a flat form using both `phx-change` and `phx-submit`.
The edit handler uses ordinary `Enum.map/2` and `%{item | label: value}`.
The hook suppresses the extra browser `change` event after an `input` event,
so LiveView does not send a second form request with its `_target` metadata.
Nested form params and checkbox, radio or file changes remain server only.
Place a marked `phx-change` on the form; a marked child input inside a form
fails compilation with guidance because LiveView's form payload is different.
The hook targets the stable component root when sending a predicted event, so
removing the clicked button locally does not cancel its server delivery.
`/native-counter` runs the opt-in component;
`/native-counter-server` runs the same render and handlers without LiveLift. These paths are also tested
in Chromium with delayed responses, consecutive clicks, server-only reset and
reconnect. This is an early supported subset of the new API, not a claim that
arbitrary LiveComponents compile to JavaScript.


Apps that use esbuild can [load each island on demand](island-loading-spike.md).
