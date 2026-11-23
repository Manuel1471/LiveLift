# Supported client language

LiveLift compiles a bounded subset of Elixir in a routed LiveView or
LiveComponent. Its native API accepts literal `~H`, static `phx-click`,
`phx-change`, `phx-submit`, `phx-value-*`, `phx-target={@myself}`, bounded
nested `params["name"]` reads, and supported chains of `assign/3`,
`update/3`, and `assign_new/3` in a marked `handle_event/3`. Use
`@client true` for optimistic synchronization and `@client :local` for
synchronous transient display state. Unsupported syntax raises an error
with a source location. See [the component guide](native-livecomponent.md).

Examples using `client_template`, `$click`, `$server`, or `event.value` describe
the deprecated API. Native apps use HEEx, `phx-*` bindings and handler params.
See the [migration guide](liveview-migration-diff.md).
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

### Native click commands

In `phx-click`, use literal, fully qualified `Phoenix.LiveView.JS` calls to
`focus`, `focus_first`, `add_class`, `remove_class`, or `toggle_class`.
Use the bound element or select descendants with `to: {:inner, "#id"}`
or `to: {:inner, ".class"}`. Pipes run in native LiveView order, with up to
eight calls. The [native counter fixture](https://github.com/Manuel1471/LiveLift/blob/main/examples/demo/lib/live_lift_demo_web/live/native_counter_component.ex)
uses these same bindings.

Phoenix executes the commands. A class effect stays on its target while
LiveLift reuses that DOM node. Changes to the template's other classes
still apply. Each class call accepts one to eight space-separated names
with letters, digits, underscores or hyphens, starting with a letter or
underscore and limited to 64 characters per name. Class persistence uses
the default LiveView selector behavior and requires immediate click bindings.
[E053](errors/E053.md) lists unsupported forms.

A native `JS.dispatch("workspace:preview", bubbles: false)` binding lets
the app listen for a custom DOM event. Write the full
`Phoenix.LiveView.JS.dispatch` call with a literal `namespace:event` name
and an explicit `bubbles: false`. The namespace starts with a lowercase
ASCII letter, has up to 24 characters, and accepts lowercase letters,
digits and hyphens. The event starts with a lowercase ASCII letter, has up
to 32 characters, and also accepts underscores. The namespaces `phx`,
`phoenix`, `live-lift` and `livelift` are reserved.

The command supports the bound element or a simple literal `{:inner, ...}`
selector. It can share a pipe with focus commands. Write class commands in
a separate binding. App code can listen on the target or during the capture
phase, as in the [demo's dialog listener](https://github.com/Manuel1471/LiveLift/blob/main/examples/demo/assets/js/app.js).
The native event includes `detail.dispatcher`.

### Optional form drafts

Add `data-live-lift-draft={@draft_scope}` to each text input or textarea
whose contents should survive a reload in the current tab. Give the
field a unique name within its form. Use an `id` and `phx-submit` on the
form. If it also uses `phx-change`, set `phx-auto-recover="ignore"` for
that form. This keeps reconnect recovery from sending a restored draft
as a validation event. Ordinary edits can still run `phx-change`.
[E054](errors/E054.md) documents incompatible markup.

```heex
<form id="native-note" phx-change="validate" phx-submit="save" phx-auto-recover="ignore" phx-target={@myself}>
  <label>Note <input name="profile[note]" value={@note_value} data-live-lift-draft={@draft_scope} /></label>
  <button type="submit">Save note</button>
  <button type="reset">Discard draft</button>
</form>
```

Set the scope from the app to a stable, opaque identifier for the
signed-in session and the record. Scopes use 1 to 128 ASCII letters, digits,
underscores or hyphens. For instance, a server-generated digest of the
session and record IDs can be used. Form IDs and field names are bounded
to 128 characters. Keep sensitive fields outside the opt-in. The
[native demo](https://github.com/Manuel1471/LiveLift/blob/main/examples/demo/lib/live_lift_demo_web/live/native_form_component.ex)
uses a synthetic scope.

LiveLift stores one versioned record per field in `sessionStorage`. A
draft has up to 4,096 UTF-16 code units and is eligible for restore for
30 minutes after the last edit. The existing server value supplies the
form when storage is unavailable or the record is invalid. An eligible
draft survives renders of its field. Restoring changes the displayed
text without triggering a LiveView event. The normal form submit sends
the current text to Phoenix for validation. A native form reset clears
the stored drafts. A submit attempt keeps the draft available because
server validation can reject it.

## Action expressions

### Ecto changeset values

Marked handlers can read `.valid?` or use `Ecto.Changeset.get_field/2` on a
schemaless string changeset. Ecto runs the original pipeline on the server.
The generated JavaScript computes the same boolean or field value. For
example, a marked event can call this local helper with
`socket.assigns.profile` and `params["profile"]`.

```elixir
defp valid_profile?(data, params) do
  (Ecto.Changeset.cast({data, %{name: :string, code: :string}}, params, [:name, :code])
   |> Ecto.Changeset.validate_required([:name, :code])
   |> Ecto.Changeset.validate_length(:name, min: 2, max: 40)
   |> Ecto.Changeset.validate_format(:code, ~r/\A[A-Z]{2}\z/)).valid?
end
```

Use fully qualified Ecto calls, a literal type map, one to 32 distinct
cast fields, and string or `nil` base values. Casting uses Ecto's default
empty values. Required validation can remove a blank change. Length and
format validations run on changed, non-`nil` values. Length counts graphemes
and accepts literal `min` and `max`, or `is` by itself.

Format accepts an unflagged literal regex with both anchors
(`\A...\z` or `^...$`), ASCII literals and positive character classes, fixed
repeats from 1 to 99, and at most one `+` or `?` repeat. The pattern body can
be up to 128 bytes. An Ecto `$` permits one trailing line feed, which the
generated pattern also permits. Keep other regex forms and changeset options
on the server.

For a Phoenix form backed by the same pipeline, use
`Phoenix.HTML.Form.input_value(form, :field)` or `form[:field].value` for the
displayed value. Use `Phoenix.Component.used_input?(form[:field])` to read
Phoenix's existing usage metadata. A local helper can build the form using
fully qualified `Phoenix.Component.to_form/2`, with literal `:action`,
`:as`, and `:id` options.

`Enum.map(form[:field].errors, fn {message, opts} -> ... end)` can return
safe values computed from the message and `Keyword.get(opts, :count)`.
This preserves Phoenix's error order and suppresses form errors for a
`nil` or `:ignore` action. See the [compiled parity fixture](https://github.com/Manuel1471/LiveLift/blob/main/bench/changeset_parity.exs)
and [E052](errors/E052.md) for the rejection boundary.

For forms with a marked handler that reads `used_input?/1`, LiveLift adds
Phoenix's ordinary `_unused_<field>` parameters during form changes. They
count toward the existing event parameter limits. Submitting the form marks
its controls used, and resetting the form clears usage. Hidden fields and
the native `phx-no-unused-field` attribute follow Phoenix's convention.

### Timers

Marked native LiveComponent handlers support a single
`Phoenix.LiveView.send_update_after(socket.assigns.myself, [field: literal], delay)`
followed by `{:noreply, socket}`. This schedules a one-shot assignment; the
synchronous handler state is unchanged. See the
[timer example and limits](native-livecomponent.md) for reconciliation and
the supported patch shape. Process mailbox callbacks are outside this
LiveComponent form.

A routed LiveView can opt in with `use LiveLift` beneath its LiveView
declaration. A marked event can call `Process.send_after(self(), :tick, 250)`
and return `{:noreply, socket}`. The first matching `handle_info(:tick, socket)`
must be unguarded and return a socket updated by the supported synchronous
operations. LiveLift derives that callback automatically. Both the message
atom and the delay (0 to 60,000 milliseconds) are literals. The scheduler
handles one message per call and shares the 32-timer instance limit.
Other destinations, dynamic payloads, and callbacks using effects such as
I/O belong in unmarked server code.

The browser applies the callback in the order the local timer fires, after
any pending actions already taken. The LiveView runs the original
`handle_info/2` on its current assigns when its own process timer fires. The
result is authoritative when network delay changes the execution order.
Try the native timer demo at `/native-timer` in the example app.

### General expressions

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
`Enum.with_index/2` with a two-argument anonymous callback that returns safe
state values;
`Enum.reverse/1`; `Enum.take/2`, `Enum.drop/2`
(including negative counts), `Enum.uniq/1`; `Map.put/3`; and
`Map.get/2,3` and `Map.delete/2` with atom keys; shallow `Map.merge/2`;
`Map.take/2` with a literal list of atom keys (missing keys are omitted);
counting `Map.keys/1` or `Map.values/1` with `length/1` or `Enum.count/1`;
`map |> Map.keys() |> Enum.map(&Atom.to_string/1) |> Enum.sort()` for sorted
names from safe atom-keyed state maps. Bare projections are rejected because
map iteration order is unspecified. Use an explicitly ordered list when the
order of values matters. See the [map iteration spike](map-iteration-spike.md).

`List.delete/2` removes the first exact match. This includes the distinction
between integers and floats in nested lists and maps. `List.replace_at/3`
and `List.delete_at/2` leave the list unchanged when the index is out of
range. Negative indexes count from the end. For `List.insert_at/3`, index
`-1` appends, other negative indexes count insertion positions from the
end, and indexes outside the list clamp to the nearest end. Indexes must be
safe integers, and the output must respect the 10,000-item list limit.

Also supported are `Integer.to_string/1` for safe integers;
`String.trim/1`; `String.length/1`; `String.downcase/1`; `String.split/1,2,3`;
`String.replace/3,4`; and
`String.contains?/2` with a string or list
of strings as the pattern. `cond` uses one condition per clause and raises
when no condition is true. Pipes are normalized before code generation,
and `if` and `cond` evaluate only the selected branch. `case` accepts unguarded literal, list (including
`[head | tail]`), partial map with safe atom keys, variable, and `_` patterns.
It tries clauses in order and raises when none matches. Pattern matching is
type strict: `1` does not match `1.0`, and `-0.0` does not match `0.0`.
Pinned variables, tuples, guards, string-key maps, and repeated bindings stay
on the server. An empty pattern list returns `false`; an empty
string pattern matches. `String.trim/1` uses Elixir's Unicode whitespace set,
including U+0085 and excluding U+FEFF. `String.length/1` counts graphemes
with `Intl.Segmenter`; browsers without it raise an explicit error.
`String.downcase/1` applies Elixir's context-free Unicode lowercase mapping,
including `"ΟΣ" -> "οσ"`; JavaScript's whole-string `toLowerCase()` would
produce `"ος"`. The [Unicode spike](downcase-spike.md) records the full scalar
comparison on the tested runtime. Locale-specific `/2` stays on the server.
`String.split/1` uses Elixir's whitespace set and omits empty parts.
`String.split/2` accepts a string or list of nonempty string patterns; a
single empty string splits at grapheme boundaries and includes both outer
empty parts. `String.split/3` accepts literal `trim: true/false` and positive
`parts: n` options (or `:infinity`). For overlapping patterns, the earliest
and longest match wins. Regex patterns and dynamic options stay on the
server. See the [split spike](split-spike.md) for whitespace and grapheme
details.
`String.replace/3,4` accepts a string or list of nonempty string patterns,
a string replacement or a one-argument anonymous callback returning valid
UTF-8 iodata. An empty string pattern replaces at grapheme boundaries.
Matches choose the earliest position and then the longest pattern. `/4`
supports a literal `global: true/false` option; the default replaces all
matches. The replacement string is literal, including `$&` and `\\0`.
Regex patterns, dynamic options, and deprecated `insert_replaced` stay on
the server. See the [replace spike](replace-spike.md).
Unsupported calls fail at compile time. Integer-only browser arithmetic fails
if it would leave JavaScript's safe integer range. Float results must remain finite. A
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
`Enum.with_index(list, fn item, index -> result end)` starts indexes at zero
and invokes the callback once per item, in order. The callback's two parameter
names must differ. `Enum.with_index/1` and the integer-offset form of `/2`
return tuples, which cannot cross LiveLift's state boundary; keep them on the
server or use the callback form to return a map or another safe value.

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
