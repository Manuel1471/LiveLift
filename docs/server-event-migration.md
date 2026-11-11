# Migrating a legacy `$server` button

`$server="save"` is a different event contract from `phx-click="save"`.
The legacy hook sends `%{"state" => client_owned_state, "revision" => server_revision}`
to the enclosing LiveView. A native `phx-click` sends the button's `phx-value-*`
parameters; it has no automatic access to the LiveLift component's current
state or revision. Replacing the attribute alone can make a parent handler
silently discard the event or save stale data.

The migrator therefore stops at `$server` with a source location and leaves the
destination unwritten. The safe migration path is:

1. Keep the existing island while moving client-owned data that must be saved
   into a normal LiveView event and server socket, or into an application service
   called by a component handler. Decide which server process owns each field.
2. Make the save button a normal `phx-click` event. Target the parent LiveView
   when its handler owns the save, or the LiveComponent when the component owns
   it. Pass only explicit, validated `phx-value-*` scalars if needed.
3. Change the server handler to read its authoritative socket or persistence
   layer. Do not trust a browser-supplied state snapshot. Keep any revision
   check that guards concurrent saves.
4. Test the save after a local edit, a delayed server response, and a reconnect.
   Copy the legacy view to a working file, remove the `$server` control from
   that copy, and run `mix live_lift.migrate` on it for the remaining
   `$click`/`$input`/`$submit` actions. Add the new server button to the
   component or parent LiveView after the generated code is reviewed.

The demo's legacy `save_score` handler in
`examples/demo/lib/live_lift_demo_web/live/counter_live.ex` checks both the
proposed count and the revision. Its `$server` button in
`examples/demo/lib/live_lift_demo/score_view.ex` cannot be rewritten as a plain
`phx-click` without changing that contract. The native opt-in component uses
its original `handle_event/3` for marked actions, so the server socket remains
authoritative for those actions.

The demo's native counter has a server-only `save` handler after a marked
optimistic `inc` handler. Its server-only counterpart has the same markup and
handler bodies. The browser test exercises both modes in Chromium, Firefox,
and WebKit and verifies that `save` reads the authoritative count.
