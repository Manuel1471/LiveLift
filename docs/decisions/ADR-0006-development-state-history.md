# ADR 0006 — Read-only development state history

Accepted 2026-11-21 for the experimental LiveLift inspector.

Developers need to see optimistic state and inspect earlier values when
diagnosing a LiveView interaction. Replaying events into LiveView would
change real application state. Applying old state to the running island
would interfere with pending actions, forms, timers and incoming replies.

Observing DOM attributes captures server snapshots but misses local
predictions. Adding event instrumentation to the shared hook charges every
app for development tooling. The [spike](../devtools-state-spike.md) showed
that a wrapper can capture state at the actual assignment and that an
explicit build definition excludes the inspector from deployed JavaScript.

Use the wrapper only for an explicitly enabled development page. Show
bounded, detached snapshots in a dialog. Moving through history affects the
dialog alone. Remove an island's history when it unmounts and keep the
remaining snapshots in memory for the current page.

Revisit this if the hook stops assigning complete state snapshots or if
browser coverage finds a snapshot that the wrapper cannot observe.
