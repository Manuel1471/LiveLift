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
`phx-target={@myself}`. Nested form params and other LiveView features remain
server only. Unsupported
forms fail during compilation with a source location and a suggestion to keep
that handler on the server.

The demo route `/native-counter` runs the opt-in component;
`/native-counter-server` runs the same render and handlers without LiveLift. These paths are also tested
in Chromium with delayed responses, consecutive clicks, server-only reset and
reconnect. This is an early supported subset of the new API, not a claim that
arbitrary LiveComponents compile to JavaScript.
