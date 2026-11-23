# LiveLift browser demo

This Phoenix app uses LiveLift through a local path dependency. From this
directory, start it with:

```sh
mix setup
mix phx.server
```

## Compare event modes

Open <http://localhost:4000/local-actions>.

- **Reverse preview** runs an `@client :local` handler. The order changes
  in the browser and no LiveView event is sent.
- **Increase shared count** runs an `@client true` handler. The browser
  predicts the new count and LiveView confirms it.
- **Select a row** sends its ID to an unmarked server handler. The selected
  row updates without disturbing the local order. Reload the page to reset
  the preview.

## Explore native components

| Route | What to try |
| --- | --- |
| [Counter](http://localhost:4000/native-counter) | Compare an optimistic counter with its [server-only view](http://localhost:4000/native-counter-server). |
| [List](http://localhost:4000/native-list) | Rename and reorder keyed rows. |
| [Form](http://localhost:4000/native-form) | Try draft recovery and submit through LiveView. |
| [Timer](http://localhost:4000/native-timer) | Compare a timed prediction with its server result. |

`mix setup` and `mix assets.build` regenerate the browser registry and
runtime in `assets/js`. Rebuild assets after editing a marked handler or
its HEEx. This demo uses in-memory state. Run `mix test` for the app's
server tests and `mix live_lift.test --cases test/live_lift_cases.json`
for Elixir and JavaScript parity.
