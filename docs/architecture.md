# Architecture notes

## Goal

Let a LiveView page opt in to browser-local interactions written as a
restricted subset of Elixir. LiveView remains responsible for server
state, persistence, navigation, and server-rendered diffs.

## Current prototype

The application writes ordinary HEEx and marks one subtree with the `LiveLift`
hook and `phx-update="ignore"`. `LiveLift.Client` retains a small Elixir
action's AST, and `mix live_lift.compile` emits a JavaScript function. The hook
holds a JSON map of local integer state. On a click it calls a compiled action
named by `data-live-lift-action`, then updates only nodes marked with
`data-live-lift-text`. The app owns the HTML structure and action names. No
event is sent to the server on a local click.

This gives the client and server separate DOM ownership. It also means the
island cannot reflect later server updates without a deliberate protocol.

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
