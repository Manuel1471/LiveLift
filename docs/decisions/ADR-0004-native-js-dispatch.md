# ADR-0004 — Use native custom events for local JavaScript

Accepted for experimental LiveLift 5.3. This record is for compiler and
runtime maintainers.

The [dispatch spike](../native-js-dispatch-spike.md) verifies that local
delivery works through Phoenix's public `JS.dispatch` command. A new
function registry would need a parallel app configuration and execution
path. Accepting arbitrary event options would admit simulated UI events,
global selectors and dispatch that can block the LiveView UI.

Compile only an explicit app-owned event name with `bubbles: false`.
The binding can address itself or select a simple descendant. Reject
browser event names, reserved namespaces, payloads and blocking options.
Reject class mutations in the same command chain because an app listener
can synchronously change the DOM that Phoenix and LiveLift would use to
calculate a class effect.

Use Phoenix's native encoding and delivery. The application's JavaScript
listens using ordinary DOM events. Ancestor capture listeners can observe
the event. An app-owned listener can open a native dialog in the demo,
outside the island where LiveView owns the markup.
