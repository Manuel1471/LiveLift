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

Open <http://localhost:4000>. Click “Add step” in the app-owned UI, then click
the server counter. The local score should stay where you left it while the
server count changes.

The `mix setup` and `mix assets.build` aliases regenerate
`assets/js/generated_views.js` before bundling. The file is ignored by Git;
edit the Elixir actions and rebuild assets to change browser behavior.

The demo has no database. To run its tests: `mix test`.
