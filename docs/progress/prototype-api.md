# Pre-release prototype API

This note preserves the template and state examples used during development
before the first Hex release. The current API uses ordinary Phoenix HEEx and
marked `handle_event/3` callbacks. See the [current Phoenix guide](../phoenix-integration.md).

## Prototype template and migration

The earlier API remains available and emits migration warnings. For a simple
legacy click view, generate a separate native component:

```sh
mix live_lift.migrate lib/my_app/score_view.ex \
  --module MyAppWeb.ScoreComponent \
  --output lib/my_app_web/components/score_component.ex
```

The command converts a literal template with `$click` buttons, text or textarea
`$input`, select `$change`, bounded map `$submit` forms, and `defclient` actions that update state fields with a map update. A
text input's `event.value` becomes the ordinary flat `params["value"]` from
`phx-change`; the generated control gets `name="value"` when needed. Select
options can keep `selected={@field}`. A submit action's `event.params.field`
becomes `params["field"]`; `event.params.profile.note` becomes
`params["profile"]["note"]` when the form contains `name="profile[note]"`.
Mismatched paths are rejected. It parses
the template and checks the generated handler against the native compiler
before writing. It leaves the original file untouched and refuses to overwrite
the destination. Review the new component, pass its initial fields as assigns,
and replace the old `<LiveLift.View.island>` mount with `<.live_component>`.
Multiple fields are converted together; each expression reads the original
`socket.assigns`, matching a legacy map update. `$server` buttons need the
[server event migration guide](../server-event-migration.md); checkbox and radio controls,
array form fields, list directives, conditional action bodies, extra module
declarations, and other constructs stop with a source-located error; they need
manual migration because their state or event semantics differ. The command
does not alter the enclosing LiveView or its server handler.

The legacy API remains useful while those views migrate. Define a view in your
own app:

```elixir
defmodule MyAppWeb.ScoreClient do
  use LiveLift.Client

  client_template """
  <section>
    <button type="button" $click="add">Add</button>
    <output>{@count}</output>
    <progress value="{@count}" max="20"></progress>
    <button type="button" $server="save_score">Save</button>
  </section>
  """

  defclient add(state), do: %{count: state.count + 1}
end
```

Use the same [asset integration](../phoenix-integration.md#manual-asset-integration) for legacy views.

Mount the view in a LiveView template:

```heex
<LiveLift.View.island
  id="score-client"
  module={MyAppWeb.ScoreClient}
  state={%{count: 10}}
/>
```

To receive `$server="save_score"`, handle and validate the client payload:

```elixir
def handle_event("save_score", %{"state" => %{"count" => count}}, socket)
    when is_integer(count) and count >= 0 and count <= 20 do
  {:noreply, assign(socket, :saved_score, count)}
end
```

Run `mix assets.build` and start Phoenix. The score changes in the browser;
Save sends it to LiveView. Each island needs a unique HTML `id`. Its local
state is reset if the island remounts. The [feature comparison](../comparison.md)
lists the current compiler subset and architectural limits.

To build a user-defined list or component, use the syntax in the
[language reference](../language.md). The demo's `TaskListView` and `TaskItem`
show an editable keyed list with typed event parameters, focus-preserving
updates, and a component whose events are handled by its parent view.

## Prototype state contract


Each legacy island has a single owner for every top-level state field. Fields listed in
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
Treat them as a proposed value. Validate both the domain value and the last
revision observed by the browser before accepting it:

```elixir
def handle_event("save", %{"state" => %{"count" => count}, "revision" => seen}, socket) do
  if is_integer(count) and count in 0..1_000 and seen == socket.assigns.score_revision do
    revision = socket.assigns.score_revision + 1
    socket = assign(socket, score_revision: revision, saved_count: count)
    {:noreply, LiveLift.Sync.push(socket, "score", revision, %{saved_count: count})}
  else
    {:noreply, socket}
  end
end

def handle_event("save", _params, socket), do: {:noreply, socket}
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
