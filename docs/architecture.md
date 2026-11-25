# Architecture

LiveLift adds an opt-in browser-owned island to a Phoenix LiveView page.
LiveView owns navigation, persistence, shared server state, and the DOM
outside that island. The boundary uses a LiveView hook and
`phx-update="ignore"`.

## Compilation and rendering

The native API uses a literal `~H` or Phoenix's colocated `.html.heex`
template and supported `handle_event/3` clauses. LiveView renders the
initial HTML with HEEx. LiveLift compiles the
bounded template into a validated tree and the action expressions into
JavaScript. The browser hook retains the initial DOM, validates action state,
and reconciles the nodes owned by the island. Stable keys let it move existing
rows, retaining input focus. Local function components defined in the app can
receive explicit props and use the parent island's events.

The internal LiveView parser sits behind an adapter. LiveLift uses a bounded
fallback when the parser is unavailable or returns an unexpected shape. The
fallback checks the supported subset and reports invalid input with a source
location. CI exercises both parser paths. See the
[language reference](language.md).

## Event and state ownership

An unmarked event uses a normal LiveView handler. An `@client true` event
predicts on the client and forwards its event parameters to LiveView. The
server runs the original handler on its own assigns and replies with a
versioned snapshot. A mounted `@client :local` event updates separate
transient assigns in the browser and skips LiveView transport entirely. A full
remount reinitializes those fields from server state.
See the [sync contract](sync.md) and [native guide](native-livecomponent.md).
