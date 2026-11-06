# LiveLift browser demo

This Phoenix app uses the LiveLift package through a local path dependency.
Its local counter runs `increment/1` and `decrement/1` from
`LiveLiftDemo.CounterActions` after LiveLift compiles them to JavaScript. A
second, server-owned counter triggers ordinary LiveView updates.

From this directory:

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>. Click the `+` button on the local counter, then
click the server counter. The local count should stay where you left it while
the server count changes.

The `mix setup` and `mix assets.build` aliases regenerate
`assets/js/generated_actions.js` before bundling. The file is ignored by Git;
edit the Elixir actions and rebuild assets to change browser behavior.

The demo has no database. To run its tests: `mix test`.
