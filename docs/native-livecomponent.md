# Opt in a LiveComponent

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
handlers continue through LiveView normally. A reconnect replaces local
predictions with the new server snapshot.

This path currently accepts a literal `~H` render and a marked
`handle_event/3` whose body returns `{:noreply, assign(socket, field, expr)}`
or `{:noreply, update(socket, field, &expr)}`. The expression must fit the
[client language subset](language.md). Marked handlers can read flat string
keys with `params["name"]` or `Map.get(params, "name")`. The template supports
static `phx-click`, `phx-change`, `phx-submit`, `phx-value-*`, and
`phx-target={@myself}`. A handler may bind flat params with
`%{"name" => name}` and use a single `socket |> assign(...)` or
`socket |> update(...)` pipe. Nested form params and other LiveView features remain
server only. Unsupported
forms fail during compilation with a source location and a suggestion to keep
that handler on the server.
Marked forms require unique, flat, safe input names; checkbox, radio and file
change events remain server only until their value semantics are covered.
The browser caps pending marked actions at 100 and rejects unsafe parameter
names before changing local state. There is no offline queue yet.
The server records the last acknowledged action sequence on the component
socket and returns the current snapshot for duplicate deliveries without
running the marked handler twice.
Optimistic events accept at most 64 flat string parameters and 64 KiB of
combined UTF-8 key/value content. The browser checks before predicting; the
server checks before invoking the marked handler. State limits are documented
in [the language contract](language.md).
The client applies a newer snapshot, replays unacknowledged actions and commits
the result only after rendering succeeds. Stale replies can acknowledge
pending actions without rolling back a newer server revision. The convergence
suite runs 1,000 seeded reply orders with deliberate server corrections.
Duplicate replies do not run the handler again, and a connection cut drops
pending predictions when the fresh LiveView snapshot arrives. There is no
offline replay queue; a disconnected click is not guaranteed to persist.

To turn off prediction without editing components, configure either switch:

```elixir
config :live_lift, enabled: false
config :live_lift, disabled_components: [MyAppWeb.Counter]
```

New renders use the original LiveView
markup and event path. An already mounted client reloads on its next marked
event when the server reports that the switch is off; reload active pages to
apply the switch immediately.

The demo route `/native-counter` runs the opt-in component;
`/native-counter-server` runs the same render and handlers without LiveLift. These paths are also tested
in Chromium with delayed responses, consecutive clicks, server-only reset and
reconnect. This is an early supported subset of the new API, not a claim that
arbitrary LiveComponents compile to JavaScript.
