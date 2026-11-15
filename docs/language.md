# Supported client language

LiveLift compiles a deliberately limited subset of Elixir. A module uses
`LiveLift.Client` for an island view or `LiveLift.Client.Component` for a
presentation component inside a view. Both define a literal `client_template`.
Unsupported syntax raises an error during compilation with a source location.
The native LiveComponent opt-in currently translates literal `~H`, static
`phx-click`, `phx-change`, `phx-submit`, `phx-value-*`,
`phx-target={@myself}`, bounded nested `params["name"]` reads, and one `assign/3` or
`update/3` inside a marked `handle_event/3`. See
[the component guide](native-livecomponent.md).
The exact native handler boundary is listed in the
[handler matrix](native-handler-matrix.md); unmarked handlers stay on LiveView.
Marked handlers may call private functions declared in the same component,
including functions defined after the handler and functions with several
unguarded clauses. LiveLift compiles each call through the same bounded `case`
patterns described below, so arguments are evaluated once and clauses keep
their Elixir order. A called helper with a guard or recursive call fails at
compilation with a location. A helper call with no matching clause raises at
runtime, as it does in Elixir. Leave unsupported handlers on the server.
Expansion is capped at 1,000 helper calls and 50,000 visited AST nodes per
marked handler to keep generated code bounded.
Expression pipes into supported calls also work, including local private
helpers: `socket.assigns.value |> String.trim() |> String.length()`. Each pipe
passes its left value as the first argument. Socket `assign/update` chains use
the same `|>` syntax.
Native `assign_new(socket, :field, fn -> expression end)` accepts a safe atom
field and a zero-argument callback. The initial client state may omit that
field; an existing value, including `nil`, is preserved without evaluating
the callback. The callback may read the original `socket.assigns` and must
use supported client expressions. One-argument callbacks stay on the server.
The native template path also accepts expression attributes for `class`,
`title`, `aria-label`, `value`, and `id`; class lists can use `&&` for conditional
entries. `nil` and `false` scalar attributes are omitted, as in HEEx.
Native `:for` uses the repeated element's `id={item.id}` as its stable key.
The ID must read a field of the loop item and evaluate to a unique string or
safe integer. Lists without a stable item ID remain server only.
Native `~H` may call a local function component (`<.badge label={@label} />`)
defined in the same LiveComponent with one literal `~H` body and explicit
props. LiveLift expands its client template at compilation; LiveView renders
the original function on the server. Parent handlers own events emitted inside
the function component. One default slot may be rendered with
`{render_slot(@inner_block)}`; its children retain the caller's assigns.
Named slots, remote functions, default props omitted at the call site, and
call-site directives are outside this subset and fail at build time. Encoded
static prop strings require an Elixir string expression.
`phx-value-id={item.id}` passes a scalar item value as a string event parameter;
the parameter name must be safe and cannot be `_live_lift_seq`.
Marked `phx-change` and `phx-submit` forms accept unique map field names up to
four segments, for example `profile[note]`. Handler reads use
`params["profile"]["note"]`; nested string-key map patterns are also accepted.
The hook sends a nested map to the original server handler and the generated
client action. Direct control `phx-change` still requires a flat name.
Static `phx-debounce` on an input or textarea accepts an empty value (300 ms),
`blur`, or a nonnegative integer of milliseconds up to 2,147,483,647. The
client delays prediction and server delivery together, reads the latest
control or form values, flushes on blur, and cancels a pending change on submit.
Arrays, repeated names, prefix conflicts, dynamic names, checkbox, radio,
file, and multiple-select controls remain server only. At most 64 string
leaves and 64 KiB of UTF-8 keys and values may cross the boundary. Put
`phx-change` on the form to read nested fields.

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

`defclient` supports safe integer, finite binary64 float, string, boolean, and `nil` literals;
atom-keyed maps and lists; field reads; map updates (`%{state | count: ...}`);
numeric `+`, `-`, `*`, integer-only `rem/2`, and numeric comparisons; `==`, `!=`;
`if` with `do` and optional `else` (omission returns `nil`); unary `!`;
short-circuit `&&` and `||`; `cond` and bounded `case`;
string `<>`; list `++`; `length/1`; `Enum.map/2`, `Enum.filter/2`,
`Enum.reject/2`, `Enum.any?/2`, `Enum.all?/2` with one-argument anonymous
functions; `Enum.find/2,3` with a one-argument anonymous predicate, returning
the first matching item or `nil`/the explicit default; `Enum.member?/2`;
`Enum.reduce/2,3` for lists with a two-argument anonymous callback
`fn item, accumulator -> result end` (the two parameter names must differ).
The callback receives each item before the accumulator, in list order.
`reduce/2` uses the first item as its accumulator and raises on an empty list;
`reduce/3` returns its initial value for an empty list. Also supported:
`Enum.sort_by/2` on lists with a one-argument anonymous key function;
`Enum.count/1` for list length and `Enum.count/2` with a one-argument anonymous
predicate using Elixir truthiness;
`Enum.join/1,2` for lists with a string separator;
`Enum.flat_map/2` for lists with a one-argument anonymous callback that returns
a list for every item;
`Enum.reverse/1`; `Enum.take/2`, `Enum.drop/2`
(including negative counts), `Enum.uniq/1`; `Map.put/3`; and
`Map.get/2,3` and `Map.delete/2` with atom keys; shallow `Map.merge/2`;
`Map.take/2` with a literal list of atom keys (missing keys are omitted);
`Integer.to_string/1` for safe integers;
`String.trim/1`; `String.length/1`; and
`String.contains?/2` with a string or list
of strings as the pattern. `cond` uses one condition per clause and raises
when no condition is true. `case` accepts unguarded literal, list (including
`[head | tail]`), partial map with safe atom keys, variable, and `_` patterns.
It tries clauses in order and raises when none matches. Pattern matching is
type strict: `1` does not match `1.0`, and `-0.0` does not match `0.0`.
Pinned variables, tuples, guards, string-key maps, and repeated bindings stay
on the server. An empty pattern list returns `false`; an empty
string pattern matches. `String.trim/1` uses Elixir's Unicode whitespace set,
including U+0085 and excluding U+FEFF. `String.length/1` counts graphemes
with `Intl.Segmenter`; browsers without it raise an explicit error. Unsupported
calls fail at compile time. Integer-only browser arithmetic fails if it would
leave JavaScript's safe integer range. Float results must remain finite. A
float operand produces a float result, and `1 == 1.0` is true, including inside
maps and lists. Map and list equality is structural.
`Enum.sort_by/2` computes each key once and keeps the original order when
keys compare equal. Sort keys may be any safe state value: numbers, `nil`,
booleans, maps, lists, or strings. Their order follows Elixir term order for
these types: numbers, then `false`/`nil`/`true`, maps, lists, and strings.
Maps compare by size, sorted atom keys, then values; lists compare
lexicographically. Strings compare by UTF-8 byte order, which differs from
JavaScript's default UTF-16 string order for some Unicode characters. Custom
sorters (`Enum.sort_by/3`) remain server only.
`Enum.join/1,2` converts strings, safe integers, finite floats, booleans,
`nil`, and valid nested chardata lists as Elixir's `String.Chars` does. `nil`
contributes an empty string, while floats preserve their Elixir display text,
including `-0.0`. A non-string separator, map element, or invalid Unicode
code point raises. The resulting state still obeys LiveLift's 1 MiB string
budget.
`Enum.flat_map/2` concatenates callback lists in input order. A scalar,
string, or map callback result is outside the client subset and raises. The
browser stops when the flattened list exceeds 10,000 elements; the server
result is subject to the same state limit before delivery.

State and action results must be maps with safe atom keys. Values may be safe
integers, finite binary64 floats, strings, booleans, `nil`, lists, or nested maps to a maximum depth
of 16. Keys named `__proto__`, `constructor`, or `prototype` are rejected.
Each map may have at most 1,024 fields and each list at most 10,000 elements.
The complete state tree may contain at most 50,000 nodes and 1 MiB of UTF-8
string content, including keys. Elixir validates before serializing; the
browser validates both initial state and action results before rendering. Floats
use a private tagged wire value so `1.0` and `-0.0` retain their Elixir type and
display text. App code uses ordinary floats. `Decimal` structs remain server
only; these floats are unsuitable for exact money arithmetic.
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
adapter uses Phoenix LiveView 1.2's internal tag parser and falls back to a
bounded LiveLift parser if that API changes. Future LiveView versions still
need compatibility testing before support is claimed.
