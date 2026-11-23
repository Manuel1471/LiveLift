# Client language semantics

LiveLift compiles a defined subset of Elixir. A marked handler runs as Elixir in parity tests and as generated JavaScript in the browser. A syntax
form outside this table is unsupported even if it is valid Elixir.

| Area | Contract |
| --- | --- |
| State | Top-level atom-keyed map; nested maps, lists, strings, booleans, `nil`, safe integers, and finite binary64 floats. Maximum nesting depth: 16. Floats use a private tagged wire value. |
| Numbers | Safe integers range from `-9_007_199_254_740_991` to `9_007_199_254_740_991`; integer arithmetic checks inputs and result. A float operand yields a float; nonfinite results raise. `rem/2` accepts integers only. Floats display with Elixir's `Float.to_string/1`, including `-0.0`. |
| Truthiness | Only `false` and `nil` are false. `0`, `""` and `[]` are true. `if`, `cond`, `!`, `&&`, `||`, `Enum.filter/2` and predicate functions use this rule. A `cond` without a true clause raises. |
| Equality | `==` and `!=` compare nested lists and maps structurally. Integer/float equality follows Elixir (`1 == 1.0`), including nested values. Atoms remain outside state. |
| Case patterns | `case` tries clauses in order. Literal patterns use Elixir's type-strict matching (`1` does not match `1.0`; `-0.0` does not match `0.0`); list patterns match exact length, cons patterns match nonempty lists, and atom-key map patterns require only the named keys. A missing clause raises. String-key map patterns, guards, pins, tuples, and repeated bindings remain server-only. |
| Private helpers | Marked handlers may call same-module `defp` functions with unguarded clauses that use the bounded case patterns. Arguments are evaluated once and clauses keep source order. A missing clause raises at runtime. Recursion, guarded clauses, and expansion beyond 1,000 calls or 50,000 visited AST nodes fail during compilation. |
| Maps | Keys in state are safe atoms; JSON sends their string names to JavaScript. A field read and `%{map | key: value}` require the key to exist. `Map.get/2,3` returns `nil` or its fallback for a missing key. |
| Lists | `++`, `length`, `Enum.map/filter/reject/any?/all?/member?/reverse` are supported with the documented function shapes. List order is stable unless an action changes it. |
| Strings | `<>` concatenates binaries. Selected `String` operations are available, including grapheme counting and context-free lowercase. See the [language reference](language.md#general-expressions). |
| Templates | Text and dynamic attributes are HTML-escaped on the server; the browser uses text nodes and DOM attributes. `:if` removes false/nil content. `:for` requires unique string or safe-integer keys within each loop. |
| Forms | `checked={...}` on input and `selected={...}` on option accept only booleans or `nil`. `<textarea>{@value}</textarea>` renders plain escaped text. The client reconciler updates `checked`, selected options and textarea values. |
| Native form params | Marked forms accept unique map names up to four segments (`profile[note]`). No arrays, duplicate or prefix-conflicting names, dynamic names, or unsupported controls. At most 64 string leaves and 64 KiB of UTF-8 keys and values. |
| Local actions | Local edits overlay their own display assigns for the life of the island. The server snapshot remains the base for optimistic replay. |
| Native component predictions | At most 100 marked actions may be pending. Server replies carry a revision, an acknowledged action sequence, and authoritative state. Reconnect resets the local prediction from the server snapshot. |

For unary `+`, the asset compiler checks how its BEAM handles a dynamic
negative zero. The generated action follows that behavior and preserves
recognized folded constant results. See the [signed-zero probe](https://github.com/Manuel1471/LiveLift/blob/main/docs/unary-plus-spike.md).

Invalid state, missing fields, arithmetic overflow and unsupported syntax fail
explicitly. The compiler must reject unsupported source at build time; runtime
value errors leave the previous client state intact. The client is not a trust
boundary: a LiveView handler must validate every event payload itself.

The parity suite runs 1,000 seeded action states against Elixir and generated
JavaScript, then compares 1,000 seeded server/browser DOM renders across four
template shapes. Float tests add 5,000 seeded finite bit patterns, mixed
arithmetic, nested equality, native handler parity and real Chromium, Firefox
and WebKit rendering. The property suite covers the published subset, not
arbitrary Elixir or every possible template shape.
