# Client language semantics

LiveLift compiles a defined subset of Elixir. The same `defclient` function
runs as Elixir in tests and as generated JavaScript in the browser. A syntax
form outside this table is unsupported even if it is valid Elixir.

| Area | Contract |
| --- | --- |
| State | Top-level atom-keyed map; nested maps, lists, strings, booleans, `nil`, and safe integers only. Maximum nesting depth: 16. |
| Integers | Range `-9_007_199_254_740_991..9_007_199_254_740_991`. Arithmetic checks its inputs and result. Overflow raises instead of rounding. Floats are unsupported. |
| Truthiness | Only `false` and `nil` are false. `0`, `""` and `[]` are true. `if`, `!`, `&&`, `||`, `Enum.filter/2` and predicate functions use this rule. |
| Equality | `==` and `!=` compare nested lists and maps structurally. There are no float or atom values in state, so cross-type numeric equality is outside the subset. |
| Maps | Keys in state are safe atoms; JSON sends their string names to JavaScript. A field read and `%{map | key: value}` require the key to exist. `Map.get/2,3` returns `nil` or its fallback for a missing key. |
| Lists | `++`, `length`, `Enum.map/filter/reject/any?/all?/member?/reverse` are supported with the documented function shapes. List order is stable unless an action changes it. |
| Strings | `<>` concatenates binaries. Grapheme counting, case mapping, locale-aware comparison and general `String` functions are unsupported. |
| Templates | Text and dynamic attributes are HTML-escaped on the server; the browser uses text nodes and DOM attributes. `:if` removes false/nil content. `:for` requires unique string or safe-integer keys within each loop. |
| Forms | `checked={...}` on input and `selected={...}` on option accept only booleans or `nil`. `<textarea>{@value}</textarea>` renders plain escaped text. The client reconciler updates `checked`, selected options and textarea values. |
| Server sync | Browser actions own every field except `server_fields`. Server patches must have increasing revisions. On reconnect, a newer server snapshot updates only server-owned fields. |
| Native component predictions | At most 100 marked actions may be pending. Server replies carry a revision, an acknowledged action sequence, and authoritative state. Reconnect resets the local prediction from the server snapshot. |

Invalid state, missing fields, arithmetic overflow and unsupported syntax fail
explicitly. The compiler must reject unsupported source at build time; runtime
value errors leave the previous client state intact. The client is not a trust
boundary: a LiveView handler must validate every event payload itself.

The parity suite runs 1,000 seeded action states against Elixir and generated
JavaScript, then compares 1,000 seeded server/browser DOM renders across four
template shapes. Real Chromium tests cover forms, focus, entities and server
patches. The property suite covers the published subset, not arbitrary Elixir
or every possible template shape.
