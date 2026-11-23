# Migrate a Phoenix LiveComponent in place

Use this guide after [installing LiveLift](phoenix-integration.md). Start
with one frequent interaction that the audit reports as compatible.

## Audit the existing component

```sh
mix live_lift.audit --path lib/consumer_lift_web/live/counter_component.ex
```

In the [server-side counter fixture](https://github.com/Manuel1471/LiveLift/blob/main/test/integration/fixtures/counter_component.ex),
`inc` updates the count, `preview` schedules a label update, and `save`
uses the current server count. In your app, use the path to the component
you want to migrate.

## Add the opt-in

The diff adds `use LiveLift` and marks two events in the counter.
For a first migration, mark just the event you chose from the audit.
Keep `~H`, `phx-target={@myself}`, the existing component mount and
each handler body as they are.

```diff
--- a/lib/consumer_lift_web/live/counter_component.ex
+++ b/lib/consumer_lift_web/live/counter_component.ex
@@ -1,5 +1,6 @@
 defmodule ConsumerLiftWeb.CounterComponent do
   use Phoenix.LiveComponent
+  use LiveLift

   def render(assigns) do
     ~H"""
@@ -12,8 +13,10 @@
     """
   end

+  @client true
   def handle_event("inc", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}

+  @client true
   def handle_event("preview", _params, socket) do
     Phoenix.LiveView.send_update_after(socket.assigns.myself, [saved: "Ready"], 50)
     {:noreply, socket}
```

`inc` can now update the counter in the browser while Phoenix runs the
same handler on its socket. The marked `preview` starts a local prediction
and schedules its authoritative update on Phoenix. `save` stays an ordinary
server event because its handler has no marker. For an event that the audit
blocks, leave its handler unmarked and follow the reported source location.

## Verify and build

Keep one parity case for every marked event and opted-in module in
your app's case file. The [parity guide](native-livecomponent.md) shows
its JSON format and the supported handler subset.

```sh
mix live_lift.test --cases test/live_lift_cases.json
mix assets.build
```

Keep the parity command in CI. Use `mix assets.deploy` for production
assets. To return this component to server mode, remove its opt-in
lines and rebuild the assets.

The [Phoenix consumer check](https://github.com/Manuel1471/LiveLift/blob/main/test/integration/phoenix_consumer.sh)
creates a separate app, runs the server fixture, and applies the exact
diff from this page. It verifies the counter and its server save again
after migration, along with parity and both asset aliases.
