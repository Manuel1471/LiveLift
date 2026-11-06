# Architecture

LiveLift adds an opt-in browser-owned island to a Phoenix LiveView page.
LiveView continues to own navigation, server state, persistence, and every
DOM node outside that island. The boundary uses `phx-update="ignore"`.

An app module defines `client_template` and `defclient` actions. The template
is parsed into a validated tree with source locations. The same tree renders
escaped initial HTML on the server and is encoded into the browser registry.
The compiler turns the supported action expressions into JavaScript and
refuses unsupported syntax. Tests execute representative actions in both
Elixir and JavaScript to detect semantic differences.

The browser hook retains the initial server-rendered DOM. An action validates
its resulting state, builds the desired tree, and patches existing nodes.
Repeated elements require stable keys; keyed nodes are moved or updated in
place, preserving input focus. `:if` can add and remove nodes. A component is
a presentation template defined by another app module; it receives props and
dispatches its events to its parent island's actions.

An explicit `$server` event sends the current local state to the surrounding
LiveView. The server must validate it. There is no automatic two-way state
merge: a remount resets the island, and LiveView cannot patch its descendants
while `phx-update="ignore"` owns them.

The template parser currently calls an internal Phoenix LiveView 1.2 parser.
That dependency is version constrained, but compatibility must be checked
when adopting a newer LiveView release. The [language reference](language.md)
defines exactly what LiveLift supports today.
