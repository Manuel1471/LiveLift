# Supported client language

LiveLift compiles a deliberately limited subset of Elixir. A module uses
`LiveLift.Client` for an island view or `LiveLift.Client.Component` for a
presentation component inside a view. Both define a literal `client_template`.
Unsupported syntax raises an error during compilation with a source location.
The native LiveComponent opt-in currently translates literal `~H`, static
`phx-click`, `phx-change`, `phx-submit`, `phx-value-*`,
`phx-target={@myself}`, flat `params["name"]` reads, and one `assign/3` or
`update/3` inside a marked `handle_event/3`. See
[the component guide](native-livecomponent.md).

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
| `checked={@enabled}`, `selected={@selected}` | Boolean attributes on inputs and options. Values must be `true`, `false`, or `nil`. |
| `<textarea>{@draft}</textarea>` | Uses the browser's native textarea value; bindings are escaped on the server. |
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
atom-keyed maps and lists; field reads; map updates (`%{state | count: ...}`);
integer `+`, `-`, `*`, `rem/2`, and numeric comparisons; `==`, `!=`;
`if` with `do` and `else`; unary `!`; short-circuit `&&` and `||`;
string `<>`; list `++`; `length/1`; `Enum.map/2`, `Enum.filter/2`,
`Enum.reject/2`, `Enum.any?/2`, `Enum.all?/2` with one-argument anonymous
functions; `Enum.member?/2`; `Enum.reverse/1`; `Map.put/3`; and
`Map.get/2,3` with atom keys; `String.trim/1`; `String.length/1`; and
`String.contains?/2` with a string or list
of strings as the pattern. An empty pattern list returns `false`; an empty
string pattern matches. `String.trim/1` uses Elixir's Unicode whitespace set,
including U+0085 and excluding U+FEFF. `String.length/1` counts graphemes
with `Intl.Segmenter`; browsers without it raise an explicit error. Unsupported
calls fail at compile time. Browser
arithmetic fails if it would leave JavaScript's safe integer range. Map and
list equality is structural.

State and action results must be maps with safe atom keys. Values may be safe
integers, strings, booleans, `nil`, lists, or nested maps to a maximum depth
of 16. Keys named `__proto__`, `constructor`, or `prototype` are rejected.
Each map may have at most 1,024 fields and each list at most 10,000 elements.
The complete state tree may contain at most 50,000 nodes and 1 MiB of UTF-8
string content, including keys. Elixir validates before serializing; the
browser validates both initial state and action results before rendering.
Initial state is rendered and escaped on the server. Keyed nodes are patched
in place in the browser, preserving input focus while editing. Local state
resets if its LiveView island remounts. Server-owned fields can receive explicit
versioned patches as described in the [sync contract](sync.md).

LiveLift does not translate arbitrary Elixir: processes, macros, protocols,
structs, binaries, and general pattern matching need semantics that JavaScript
does not provide directly. Add a supported operation only with Elixir/JavaScript
parity tests for its edge cases.

Templates are HTML with this explicit syntax, not general HEEx or `~HOLO`.
Executable HTML tags and inline JavaScript attributes are rejected. The
parser currently uses Phoenix LiveView 1.2's internal tag parser, so future
LiveView versions need compatibility testing before support is claimed.
