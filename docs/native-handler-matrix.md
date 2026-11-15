# Native `@client` handler matrix

This is the current experimental surface of a marked `handle_event/3`. An unmarked
handler remains a normal LiveView server handler. A marked handler runs its
original Elixir body on the server and generated JavaScript for prediction.
The seeded language corpus and app parity cases compare those paths. Source locations and alternatives
for unsupported forms are tested in `test/live_lift/component_test.exs`.

| Roadmap form | Client status | Boundary |
| --- | --- | --- |
| Handler header and event params | Supported subset | One literal event name, one clause, no guard; `_params`, flat or nested string-key map pattern, or `params["key"]` / `Map.get(params, "key")` through four safe segments. Other patterns stay on the server. |
| `socket`, `assign/3`, `update/3`, `assign_new/3`, pipe | Supported subset | Return `{:noreply, socket}` after these operations; socket chains and expression calls work with `|>`. `assign_new` accepts an atom key and a zero-argument callback whose expression is in the client language. A present key, including `nil`, skips the callback. One-argument callbacks and other socket operations stay on the server. |
| Integers and decimals | Finite binary64 floats and safe integers | Mixed `+`, `-`, `*`, comparisons and `==` follow the documented subset. `Decimal` structs and arbitrary numeric functions stay on the server. |
| `if`, `case`, `cond`, `defp` | `if`, bounded `case` and `cond`, local `defp` | `if` with optional `else` and `cond` use Elixir truthiness. `case` accepts unguarded literal, list, partial map, variable, and `_` patterns with type-strict matching. Same-module private helpers may have several unguarded clauses and call other helpers. Guards, pins, tuples, repeated bindings, and recursion remain server-only. |
| `Enum.find/2,3` | Supported subset | List input and one-argument anonymous predicate. Returns first item with an Elixir-truthy predicate result; otherwise `nil` or the supplied default. |
| `Enum.reduce/sort_by/count/join/flat_map/with_index` | Server only | These operations are rejected with source location. |
| Other `Enum` operations | Supported subset | `map/filter/reject/any?/all?` with one-argument anonymous functions, `member?/2`, `reverse/1`, `take/2`, `drop/2`, and `uniq/1`; see [language semantics](language.md). |
| `String.downcase/split/replace` | Server only | These operations are rejected with source location. |
| Other `String` operations | Supported subset | `trim/1`, `length/1`, `contains?/2`; see Unicode limits in [language semantics](language.md). |
| `Map.keys/values` and `List` module operations | Server only | Map iteration order differs between Elixir and JavaScript. These operations are rejected. |
| Other `Map` operations | Supported subset | Atom-keyed `put/get/delete`, shallow `merge`, and `take` with a literal atom-key list. |

The server remains the right place for unsupported forms today. Remove `@client true`
from that handler; its `~H` and `phx-*` code continue to use LiveView. This
matrix does not imply support for arbitrary Elixir, macros, structs, or
processes. The phase 2 roadmap calls for broader support than this snapshot;
the rejected cells remain tracked work.

Before changing a server-only cell to supported, define its exact semantics in
`language.md`, add Elixir/JavaScript parity cases including failures and limits,
prove the rendered result in a browser when it affects the DOM, then benchmark
the generated code path. Keep a compile-time rejection test for nearby forms.
