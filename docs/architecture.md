# Architecture notes

## Goal

Let a LiveView page opt in to browser-local interactions written as a
restricted subset of Elixir. LiveView remains responsible for server
state, persistence, navigation, and server-rendered diffs.

## Current prototype

The application defines a `LiveLift.Client` module with `client_template` and
`defclient` actions. The template compiler turns `{@field}` and `$click` into
DOM bindings. `LiveLift.View.island/1` renders initial HTML on the server and
creates a `phx-update="ignore"` boundary. `mix live_lift.compile` discovers
the app's views and emits their templates and actions as a JavaScript registry.
On mount, the browser uses the matching template and stores a local JSON map
of integer state. On a click it runs a
compiled action and updates the bound text nodes. The app owns the view's
markup and actions. No event is sent to the server on a local click.

This gives the client and server separate DOM ownership. It also means the
island cannot reflect later server updates without a deliberate protocol. The
current renderer updates text nodes; it is not Hologram's general renderer.

## Next technical questions

- How does a local component send a final result to `handle_event/3`?
- When the server changes the initial data, should the local state reset,
  rebase, or remain untouched? This must be explicit per component.
- Which additional pure Elixir forms can be compiled without pulling in a full
  runtime? Hologram's compiler and interpreter are useful references, but its
  renderer and LiveView's diff protocol have different ownership models.
- How do local changes behave across reconnects and navigation?

The package should grow only after an end-to-end use case demonstrates the
needed state and synchronization contract.
