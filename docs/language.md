# Supported client language

LiveLift compiles a deliberately limited subset of Elixir. A module uses
`LiveLift.Client` for an island view or `LiveLift.Client.Component` for a
presentation component inside a view. Both define a literal `client_template`.
Unsupported syntax raises an error during compilation with a source location.

## Template bindings

| Syntax | Behavior |
| --- | --- |
| `{@name}` or `{@item.name}` | Escaped text binding. Collections cannot be displayed directly. |
| `class="{@tone}"` | Dynamic `class`; also supported: `title`, `aria-label`, `value`. |
| `$show="visible"` | Keeps the element mounted; sets `hidden` when the field is `false` or `nil`. |
| `:if={@visible}` | Adds or removes the element with Elixir truthiness. |
| `:for={item <- @items} :key={item.id}` | Repeats an element for a list. Keys must be unique strings or safe integers. |
| `$click="action"` | Runs a client action on click. |
| `$input="action"`, `$change="action"`, `$submit="action"` | Runs a client action for the named DOM event. Submit prevents the browser default. |
| `:params={%{id: @item.id}}` | Passes typed parameters to the action in `event.params`. |
| `$server="event"` | Sends the current local state to the enclosing LiveView's `handle_event/3`. |

Events receive `event.value`, `event.checked`, and `event.params`. Define
`defclient action(state, event)` to use them. One-argument actions remain valid.
Components are referenced by their full module name, for example
`<MyApp.TaskItem item={item} />`. Component props are Elixir expressions from
the template subset. Components can contain event bindings; their parent view
owns the actions and state. Components have no slots or independent state yet.

## Action expressions

`defclient` supports safe integer, string, boolean, and `nil` literals;
atom-keyed maps and lists; field reads; integer `+`, `-`, `*`; `==`, `!=`;
`if` with `do` and `else`; unary `!`; list `++`; `length/1`;
`Enum.map/2`, `Enum.reject/2` with one-argument anonymous functions;
`Enum.reverse/1`; and `Map.put/3` with an atom key. Unsupported calls fail
at compile time. Browser arithmetic fails if it would leave JavaScript's safe
integer range. Map and list equality is structural.

State and action results must be maps with safe atom keys. Values may be safe
integers, strings, booleans, `nil`, lists, or nested maps to a maximum depth
of 16. Keys named `__proto__`, `constructor`, or `prototype` are rejected.
Initial state is rendered and escaped on the server. Keyed nodes are patched
in place in the browser, preserving input focus while editing. Local state
resets if its LiveView island remounts; `$server` does not automatically merge
server assigns back into the island.

Templates are HTML with this explicit syntax, not general HEEx or `~HOLO`.
Executable HTML tags and inline JavaScript attributes are rejected. The
parser currently uses Phoenix LiveView 1.2's internal tag parser, so future
LiveView versions need compatibility testing before support is claimed.
