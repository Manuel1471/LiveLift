# Add LiveLift to a Phoenix LiveView app

LiveLift is currently an experimental package in this repository. Use a path
dependency while developing alongside it:

```elixir
# mix.exs
{:live_lift, path: "../LiveLift"}
```

Run `mix deps.get`. Define a view in your own app:

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

Add generation before your asset bundler in the `assets.build` and
`assets.deploy` aliases in `mix.exs`:

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
