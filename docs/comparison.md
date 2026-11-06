# LiveLift, LiveView, and Hologram

LiveLift lets one Phoenix LiveView page contain a browser-owned view defined in
Elixir. It compiles a restricted set of `defclient` expressions and template
bindings to JavaScript. A `phx-update="ignore"` boundary keeps that view's DOM
out of LiveView's normal patching. An explicit `$server` binding can send the
local state to `handle_event/3`.

| Aspect | Phoenix LiveView | Hologram | LiveLift today |
| --- | --- | --- | --- |
| Main runtime | Elixir on the server; browser receives DOM updates | Elixir application code compiled for the browser | LiveView on the server plus selected Elixir client views compiled to JavaScript |
| Browser interactions | Usually events sent to the server; LiveView JS commands and hooks also run locally | Client-side component and page runtime | `defclient` actions update a local island immediately |
| Templates | HEEx | `~HOLO` | `client_template` with a small set of bindings |
| Server communication | Built into LiveView events | Hologram's own server interaction model | Explicit `$server` event sends local state to LiveView |
| Adoption | Phoenix application | Hologram application architecture | Add a package and mount an island inside an existing LiveView |

## What works

- The app authors its own markup and actions in Elixir. LiveLift does not ship
  prefabricated UI components for those interactions.
- The server renders the first HTML with escaped state values. The browser
  keeps those nodes on mount and handles later local actions without a round
  trip.
- The app can deliberately send local state to a LiveView event. The demo
  verifies that a server update does not reset the local island.
- Unsupported client expressions fail at compile time instead of silently
  falling back to server execution.

## Tradeoffs and current limits

- The compiler covers only a small, explicit subset of Elixir. It supports
  keyed lists, conditional nodes, and presentation components, but does not
  compile arbitrary functions, dependencies, processes, or full HEEx. The
  exact subset is in the [language reference](language.md).
- State can contain JSON-safe nested maps and lists. The client and server do not
  share one automatically synchronized state store. A server event is a
  deliberate transfer, and the server must validate its payload.
- `phx-update="ignore"` assigns DOM ownership to the client island. LiveView
  cannot patch its descendants in the normal way. Remounting loses local state.
- JavaScript is added to the asset bundle. There are two runtimes to debug,
  and the current implementation has no source maps or benchmark evidence.
- Hologram has a broader compiler and client runtime. LiveLift is an
  incremental extension experiment for LiveView, not a Hologram replacement.

The main benefit is selective client behavior inside an existing LiveView
application. The main engineering cost is maintaining matching Elixir and
JavaScript semantics while keeping ownership and state flow explicit.
