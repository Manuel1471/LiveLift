# Native `@client` handler matrix

This is the current experimental surface of a marked `handle_event/3`. An unmarked
handler remains a normal LiveView server handler. `@client true` predicts and
confirms via LiveView. `@client :local` uses the synchronous subset and runs
only in the mounted browser, with separate write fields.
The seeded language corpus and app parity cases compare those paths. Source locations and alternatives
for unsupported forms are tested in `test/live_lift/component_test.exs`.

| Roadmap form | Client status | Boundary |
| --- | --- | --- |
| Handler header and event params | Supported subset | One literal event name, one clause, no guard; `_params`, flat or nested string-key map pattern, or `params["key"]` / `Map.get(params, "key")` through four safe segments. Other patterns stay on the server. |
| `socket`, `assign/3`, `update/3`, `assign_new/3`, pipe | Supported subset | Return `{:noreply, socket}` after these operations; socket chains and expression calls work with `|>`. `assign_new` accepts an atom key and a zero-argument callback whose expression is in the client language. A present key, including `nil`, skips the callback. One-argument callbacks and other socket operations stay on the server. |
| Integers and decimals | Finite binary64 floats and safe integers | Mixed `+`, `-`, `*`, comparisons and `==` follow the documented subset. `Decimal` structs and arbitrary numeric functions stay on the server. |
| `if`, `case`, `cond`, `defp` | `if`, bounded `case` and `cond`, local `defp` | `if` with optional `else` and `cond` use Elixir truthiness. `case` accepts unguarded literal, list, partial map, variable, and `_` patterns with type-strict matching. Same-module private helpers may have several unguarded clauses and call other helpers. Guards, pins, tuples, repeated bindings, and recursion remain server-only. |
| `Enum.find/2,3` | Supported subset | List input and one-argument anonymous predicate. Returns first item with an Elixir-truthy predicate result; otherwise `nil` or the supplied default. |
| `Enum.reduce/2,3` | Supported subset | List input and two-argument anonymous callback; `/2` uses the first element as its accumulator and rejects an empty list, while `/3` returns the initial accumulator on an empty list. |
| `Enum.sort_by/2` | Supported subset | List input and one-argument anonymous key function; stable Elixir term order for safe state values. Custom sorters in `/3` stay on the server. |
| `Enum.count/1,2` | Supported subset | List length or one-argument anonymous predicate with Elixir truthiness. |
| `Enum.join/1,2` | Supported subset | List values that implement the published `String.Chars` subset; `/2` requires a string separator. Maps and unsupported values raise. |
| `Enum.flat_map/2` | Supported subset | List input and one-argument anonymous callback returning a list; flattened output is capped at 10,000 elements. |
| `Enum.with_index/2` callback form | Supported subset | List input and two-argument anonymous callback returning a safe state value; indexes start at zero. Tuple-producing `/1` and offset `/2` fail at compile time with a source-located alternative. |
| Other `Enum` operations | Supported subset | `map/filter/reject/any?/all?` with one-argument anonymous functions, `member?/2`, `reverse/1`, `take/2`, `drop/2`, and `uniq/1`; see [language semantics](language.md). |
| `String.downcase/1` | Supported subset | Context-free Unicode lowercase mapping; locale-specific `/2` stays on the server. |
| `String.split/1,2,3` | Supported subset | Elixir whitespace, string or string-list patterns, and literal `trim`/`parts` options. Empty string uses grapheme boundaries. Regex and dynamic options remain server only. |
| `String.replace/3,4` | Supported subset | String or string-list patterns; literal string or one-argument callback replacement; literal `global` option. Empty string uses grapheme boundaries. Regex, dynamic options, and `insert_replaced` remain server only. |
| Other `String` operations | Supported subset | `trim/1`, `length/1`, `contains?/2`; see Unicode limits in [language semantics](language.md). |
| `Map.keys/1`, `Map.values/1` | Supported subset | Count either projection with `length/1` or `Enum.count/1`. Sort key names after `Enum.map(&Atom.to_string/1)`. Bare projections are rejected with a source location. |
| `List.delete/2`, `List.insert_at/3`, `List.replace_at/3`, `List.delete_at/2` | Supported subset | Exact deletion and positional edits on safe lists, including negative indexes. Tuple-based operations stay on the server. |
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
