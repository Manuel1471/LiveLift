# Add LiveLift to a Phoenix LiveView app

LiveLift 0.1.0-rc.1 is experimental and supports Phoenix LiveView 1.2.x.
The automatic installer targets the standard Phoenix 1.8 asset layout.
Choose [a new Phoenix app](#start-a-new-phoenix-app) or
[an existing Phoenix app](#adopt-livelift-in-an-existing-phoenix-app).

## Start a new Phoenix app

Create a small app with LiveView and the default assets. This example uses
an in-memory counter. See the [Phoenix generator guide](https://phx-new.hexdocs.pm/1.8.16/Mix.Tasks.Phx.New.html).

```sh
mix archive.install hex phx_new 1.8.16
mix phx.new lift_example --no-ecto --no-install
cd lift_example
```

[Add the LiveLift dependency](#add-the-dependency) in the new app's
`mix.exs`, then run the installer from the app root.

```sh
mix deps.get
mix live_lift.install
```

Create `lib/lift_example_web/live/counter_live.ex`.

```elixir
defmodule LiftExampleWeb.CounterLive do
  use LiftExampleWeb, :live_view
  use LiveLift

  def mount(_params, _session, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  def render(assigns) do
    ~H"""
    <button type="button" phx-click="inc">Count: {@count}</button>
    """
  end

  @client true
  def handle_event("inc", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end
end
```

In `lib/lift_example_web/router.ex`, add the following route inside the
existing `scope "/", LiftExampleWeb` that uses the `:browser` pipeline.

```elixir
live "/counter", CounterLive
```

Run setup to install the asset tools and build the browser registry, then
start Phoenix.

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000/counter> and click the button. The count changes
from 0 to 1 immediately, and LiveView confirms the same value on the server.

## Adopt LiveLift in an existing Phoenix app

1. Check that the app uses LiveView 1.2.x. In an umbrella, work in the app
   that owns the Phoenix endpoint and builds its browser assets.
2. [Add the dependency](#add-the-dependency), then run `mix deps.get` and
   `mix live_lift.install` in the Phoenix app. Review the changes to
   `mix.exs`, `assets/js/app.js`, and `.gitignore`. If the app uses a
   custom asset pipeline or hook factory, follow the
   [manual integration](#manual-asset-integration).
3. Audit a routed LiveView or stateful LiveComponent. Replace the example
   path with the existing module's path. The audit reports which handlers
   can compile and gives a source location when a handler is blocked.
   It checks local function components declared in the same module,
   including nested components with explicit props and a default slot.

   ```sh
   mix live_lift.audit --path lib/my_app_web/live/counter_component.ex
   ```

4. Choose one compatible handler. Add `use LiveLift` after the existing
   `use` in that module, and put `@client true` immediately before the
   handler. Keep the HEEx, event bindings, and component mount. For a
   LiveComponent, keep `phx-target={@myself}` on events that it handles.
   Save and other unmarked handlers continue through regular LiveView
   event handling. See the [verified migration diff](liveview-migration-diff.md).
5. Run `mix assets.build` and exercise the interaction in the browser.
   Verify that the surrounding page and its server events still work. Add
   the marked handler to your app's [parity cases](native-livecomponent.md#verify-parity)
   and keep `mix assets.deploy` in the deployment build. Rerun
   `mix assets.build` when you edit the opted-in HEEx or handler.

LiveLift compiles the opted-in module's `render/1` along with its marked
handlers. If the template uses unsupported HEEx, opt in a smaller
LiveComponent with the markup and events you want to run in the browser.

Use `@client :local` for a transient preview, filter, or sort that should
stay in the mounted browser. See the
[three event modes and their state rules](native-livecomponent.md#local-actions).
To return a handler to ordinary LiveView, remove its marker and rebuild the
assets. Remove `use LiveLift` from the module if you remove its last marker.

## Add the dependency

Add this entry to the existing `deps/0` list in the Phoenix app's
`mix.exs` to install the [public Hex release](https://hex.pm/packages/live_lift/0.1.0-rc.1).

```elixir
{:live_lift, "~> 0.1.0-rc.1"}
```

To try a local build, run
`mix hex.build --unpack --output /tmp/live_lift_package` from the LiveLift
checkout, then use this dependency entry in the Phoenix app instead.

```elixir
{:live_lift, path: "/tmp/live_lift_package"}
```

## Manual asset integration

LiveLift compiles opted-in modules into a browser registry. Phoenix loads
that registry using the `LiveLift` hook on the app's existing LiveSocket.
For custom asset pipelines, wire the same two pieces by hand.

1. In the existing `assets.build` and `assets.deploy` aliases in `mix.exs`,
   insert `"live_lift.compile --output assets/js/generated_views.js"` before
   the JavaScript bundler. Keep the app's current asset tasks and their order.
   LiveLift generates `assets/js/generated_views.js` and
   `assets/js/live_lift_runtime.js` with their associated source map and type
   declarations. Add the generated outputs to `.gitignore`.

   ```gitignore
   /assets/js/generated_views.js
   /assets/js/generated_views.js.map
   /assets/js/generated_views.d.ts
   /assets/js/live_lift_runtime.js
   /assets/js/live_lift_runtime.d.ts
   ```

2. Import the generated modules in the JavaScript entry point and add LiveLift
   to the hook map already passed to LiveSocket. This example uses
   `assets/js/app.js` and the standard Phoenix colocated hooks. Include any
   other hooks your app already registers.

   ```javascript
   import {createClientHook} from "./live_lift_runtime.js"
   import {views} from "./generated_views.js"

   const liveSocket = new LiveSocket("/live", Socket, {
     params: {_csrf_token: csrfToken},
     hooks: {...colocatedHooks, LiveLift: createClientHook(views)},
   })
   ```

3. Run `mix assets.build` locally and `mix assets.deploy` for deployment.
   See the [versioned asset guide](versioned-assets.md) for TypeScript and
   runtime compatibility.

## Install with Igniter

For an app that already has Igniter 0.8.5, preview and apply the installer
using Igniter's standard commands with the published Hex version.

```sh
mix igniter.install live_lift@0.1.0-rc.1 --dry-run
mix igniter.install live_lift@0.1.0-rc.1
mix assets.build
```

For local development with an unpacked Hex tarball, Igniter accepts
`live_lift@path:/path/to/package` in place of the registry version.
The installer adds the generation step before esbuild in both literal
asset alias lists, retaining existing tasks and comments. The standard
Phoenix colocated hook map gets the LiveLift hook. For dynamic aliases,
a custom hook factory, or another bundler, use the manual integration
below. The asset edits are only applied after Igniter validates the plan.
Igniter 0.8.5 can report a blocked installer with a successful process exit.
Use `--check` when verifying an existing installation in CI so issues or
pending edits cause a nonzero exit.
