# Architecture notes

## Goal

Let a LiveView page opt in to browser-local interactions, eventually written
as a restricted subset of Elixir. LiveView remains responsible for server
state, persistence, navigation, and server-rendered diffs.

## Current prototype

`LiveLift.Counter.counter/1` renders the initial HTML with HEEx. Its root has a
LiveView hook and `phx-update="ignore"`. The hook owns only the count and the
output text after mounting. No event is sent to the server on a click.

This gives the client and server separate DOM ownership. It also means the
counter cannot reflect later server updates without a deliberate protocol.

## Next technical questions

- How does a local component send a final result to `handle_event/3`?
- When the server changes the initial data, should the local state reset,
  rebase, or remain untouched? This must be explicit per component.
- Which pure Elixir forms can be compiled without pulling in a full runtime?
  Hologram's compiler and interpreter are useful references, but its renderer
  and LiveView's diff protocol have different ownership models.
- How do local changes behave across reconnects and navigation?

The package should grow only after an end-to-end use case demonstrates the
needed state and synchronization contract.
