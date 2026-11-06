# LiveLift browser demo

This Phoenix app uses the LiveLift package through a local path dependency.
`LiveLiftDemo.ScoreView` defines both the score template and the Elixir actions
`advance/1` and `retreat/1`. LiveLift compiles them to JavaScript and mounts
the view inside `CounterLive`. A second, server-owned counter triggers ordinary
LiveView updates.

From this directory:

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>. The green panel is the browser-owned Elixir
view: its score, progress chart, and milestone change immediately when you
click “+ 2 points”. The violet panel belongs to LiveView: “Trigger server
event” updates its count and event-history chart. “Sync score” sends the
current local score through a LiveView event and displays it in the server
panel. Updating the server leaves the local score intact.

The third panel demonstrates a user-defined component inside a keyed list.
Add, rename, remove, and reorder tasks. The list updates in the browser; task
inputs retain focus during edits. The tasks are local demo state and reset on
reload.

The `mix setup` and `mix assets.build` aliases regenerate
`assets/js/generated_views.js` and copy `assets/js/live_lift_runtime.js`
before bundling. Both files are ignored by Git; edit the Elixir actions and
rebuild assets to change browser behavior.

The demo has no database. To run its tests: `mix test`.
