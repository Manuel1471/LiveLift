# LiveLift browser demo

This Phoenix app uses the LiveLift package through a local path dependency.
It shows a browser-local counter beside a server-owned LiveView counter.

From this directory:

```sh
mix setup
mix phx.server
```

Open <http://localhost:4000>. Click the `+` button on the local counter, then
click the server counter. The local count should stay where you left it while
the server count changes.

The demo has no database. To run its tests: `mix test`.
