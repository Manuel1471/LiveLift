# Native `@client` handler matrix

This is the bounded v0.4 surface of a marked `handle_event/3`. An unmarked
handler remains a normal LiveView server handler. Every listed client form runs
through the original Elixir handler on the server and generated JavaScript for
prediction; app parity cases exercise both. Source locations and alternatives
for unsupported forms are tested in `test/live_lift/component_test.exs`.

| Roadmap form | Client status | Boundary |
| --- | --- | --- |
| Handler header and event params | Supported subset | One literal event name, one clause, no guard; `_params`, flat or nested string-key map pattern, or `params["key"]` / `Map.get(params, "key")` through four safe segments. Other patterns stay on the server. |
| `socket`, `assign/3`, `update/3`, pipe | Supported subset | Return `{:noreply, socket}` after `assign` or `update`; chains of those operations work with `|>`. `assign_new`, other socket operations, and general expression pipes stay on the server. |
| Integers and decimals | Safe integers only | Arithmetic and comparison require integers within JavaScript's safe range. Decimal literals and floating point operations stay on the server until a numeric model is specified. |
| `if`, `case`, `cond`, `defp` | `if` only | `if` with optional `else` uses Elixir truthiness. `case`, `cond`, and calls to local helpers are rejected for marked handlers; leave those handlers unmarked. |
| `Enum.find/reduce/sort_by/count/join/flat_map/with_index` | Server only | These operations are rejected with source location. |
| Other `Enum` operations | Supported subset | `map/filter/reject/any?/all?` with one-argument anonymous functions, `member?/2`, `reverse/1`, `take/2`, `drop/2`, and `uniq/1`; see [language semantics](language.md). |
| `String.downcase/split/replace` | Server only | These operations are rejected with source location. |
| Other `String` operations | Supported subset | `trim/1`, `length/1`, `contains?/2`; see Unicode limits in [language semantics](language.md). |
| `Map.keys/values` and `List` module operations | Server only | Map iteration order differs between Elixir and JavaScript. These operations are rejected. |
| Other `Map` operations | Supported subset | Atom-keyed `put/get/delete`, shallow `merge`, and `take` with a literal atom-key list. |

The server remains the right place for unsupported forms. Remove `@client true`
from that handler; its `~H` and `phx-*` code continue to use LiveView. This
matrix does not imply support for arbitrary Elixir, macros, structs, or
processes.

Before changing a server-only cell to supported, define its exact semantics in
`language.md`, add Elixir/JavaScript parity cases including failures and limits,
prove the rendered result in a browser when it affects the DOM, then benchmark
the generated code path. Keep a compile-time rejection test for nearby forms.
