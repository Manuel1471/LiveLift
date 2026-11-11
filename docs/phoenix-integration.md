# Add LiveLift to a Phoenix LiveView app

LiveLift 0.1.0-rc.1 is an experimental package. The parser currently requires
Phoenix LiveView 1.2.x. If its private HEEx parser changes, compilation stops
with the source file and a supported-version suggestion:

```elixir
# mix.exs
{:live_lift, "~> 0.1.0-rc.1"}
```

Run `mix deps.get` and `mix live_lift.install`. The installer checks the
standard Phoenix 1.8 colocated hook and both asset aliases before writing.
It repairs a missing compile step if only one alias was previously integrated;
an unsupported hook layout fails with an explanation and leaves the files
unchanged. For a new component, keep
ordinary LiveView syntax and add two opt-in lines:

```elixir
defmodule MyAppWeb.Counter do
  use Phoenix.LiveComponent
  use LiveLift

  def render(assigns), do: ~H"<button phx-click='inc' phx-target={@myself}>{@count}</button>"

  @client true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end
end
```

Without `use LiveLift` and `@client true`, this is a normal server component.
The [native component guide](native-livecomponent.md) lists the currently
supported templates and handlers. To check existing components before editing
them, run `mix live_lift.audit --path lib/my_app_web`. It prints a file and
line for each handler, with either `compatible` or the reason it is blocked.
This source audit does not change files; test a migrated component in the
browser before shipping it.

## Existing `client_template` apps

The earlier API remains available and emits migration warnings. For a simple
legacy click view, generate a separate native component:

```sh
mix live_lift.migrate lib/my_app/score_view.ex \
  --module MyAppWeb.ScoreComponent \
  --output lib/my_app_web/components/score_component.ex
```

The command converts a literal template with `$click` buttons and
one-argument `defclient` actions that update state fields with a map update. It parses
the template and checks the generated handler against the native compiler
before writing. It leaves the original file untouched and refuses to overwrite
the destination. Review the new component, pass its initial fields as assigns,
and replace the old `<LiveLift.View.island>` mount with `<.live_component>`.
Multiple fields are converted together; each expression reads the original
`socket.assigns`, matching a legacy map update. `$server`, input events,
list directives, conditional action bodies, extra module
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

In a standard Phoenix 1.8 app, `mix live_lift.install` adds generation
before the asset bundler in `assets.build` and `assets.deploy` and merges the
hook with Phoenix's colocated hooks. The command is safe to rerun. For a
custom app, make these changes manually:

```elixir
"assets.build": [
  "compile",
  "live_lift.compile --output assets/js/generated_views.js",
  "esbuild my_app"
],
"assets.deploy": [
  "live_lift.compile --output assets/js/generated_views.js",
  "esbuild my_app --minify",
  "phx.digest"
]
```

The command writes `generated_views.js` and `live_lift_runtime.js` into
`assets/js`. Ignore both generated files in Git. Merge the hook into the
existing LiveSocket hooks in `assets/js/app.js`:

```javascript
import {createClientHook} from "./live_lift_runtime.js"
import {views} from "./generated_views.js"

const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, LiveLift: createClientHook(views)},
})
```

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
state is reset if the island remounts. The [feature comparison](comparison.md)
lists the current compiler subset and architectural limits.

To build a user-defined list or component, use the syntax in the
[language reference](language.md). The demo's `TaskListView` and `TaskItem`
show an editable keyed list with typed event parameters, focus-preserving
updates, and a component whose events are handled by its parent view.
