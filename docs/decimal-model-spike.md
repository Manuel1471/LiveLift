# Decimal literal model spike

Phase 2 requires a numeric model before compiling Elixir decimal literals.
In Elixir, `1.0` is a binary floating point value; it is not an exact decimal
money type. The target for this phase is **finite IEEE 754 binary64 floats**,
alongside the existing safe integer subset. `Decimal` structs remain on the
server until a separate use case and wire format justify them.

## Why a plain JSON number is insufficient

The local Elixir/Node probe on OTP 29 and Node 26 produced:

| Expression | Elixir | JavaScript after JSON parsing |
|---|---|---|
| `1.0` serialized | `Jason.encode!(1.0)` is `"1.0"` | `JSON.parse("1.0")` is an integer-looking `Number`; `JSON.stringify` returns `"1"` |
| negative zero | `Jason.encode!(-0.0)` is `"-0.0"` | `JSON.stringify(-0)` returns `"0"` |
| display | `Float.to_string(7.0)` is `"7.0"` | `String(7.0)` is `"7"` |
| equality | `%{x: 1} == %{x: 1.0}` is `true` | Type information is absent from the parsed JSON value |

The [Elixir Float documentation](https://hexdocs.pm/elixir/Float.html) specifies
short float text for display. The [Erlang float conversion documentation](https://www.erlang.org/doc/apps/erts/erlang.html)
describes `float_to_binary/2` with `short`, and the
[ECMAScript JSON specification](https://tc39.es/ecma262/2022/multipage/structured-data.html)
stringifies finite numbers through its number-to-string operation. These
different spellings would change server-rendered text and could erase the
float type after one client action.

## Decision

Use an internal tagged scalar in serialized LiveLift state and generated action
results, for example `{"$live_lift_float":"1.0"}`. The tag key is outside the
allowed user map-key grammar, so it cannot collide with an app map. The string
must be a canonical, finite, round-trippable float representation and must
preserve `-0.0`. Decode it as a typed float in the JavaScript runtime. Keep
ordinary JSON numbers for safe integers. App authors continue writing ordinary
Elixir floats; this representation is private to the client boundary.

Generated arithmetic must distinguish integer and float operands: integer-only
operations keep the safe-integer check; a float operand produces a tagged float.
Equality must follow Elixir `==` for nested maps and lists. Display must match
Elixir's `Float.to_string/1`, including integral floats, negative zero and
scientific notation. State validation and size accounting must treat the tag
as one scalar while charging its serialized bytes, and reject nonfinite values.

## Gate before enabling float syntax

1. Seeded Elixir/Node round trips for float bits and display text, including
   subnormals, `-0.0`, integral floats, exponent boundaries and near-overflow.
2. Parity for mixed integer/float arithmetic, comparisons, nested equality,
   map/list storage, and client result validation; explicit errors for
   nonfinite results.
3. Server HTML versus browser DOM for `{@value}` and dynamic attributes.
4. Measure bundle and action cost on the native component route. If the
   formatter cannot match Elixir over the supported range, keep float
   expressions rejected rather than emit divergent JavaScript.

## Implementation evidence

The tagged float representation is implemented in `LiveLift.FloatWire`, the
generated action helpers, the template interpreter, and the browser runtime.
`test/live_lift/float_parity_test.exs` compares 5,000 seeded finite binary64 bit
patterns, including negative zero and subnormals, across Elixir and Node. It
also compares mixed arithmetic, relational operators, nested equality and a
server-rendered template against the browser DOM. A native marked handler is
exercised through `mix live_lift.test` in `test/live_lift/test_task_test.exs`.
The `/native-float` demo confirms initial `-0.0`, optimistic `0.5`, and
authoritative `1.0` in Chromium, Firefox, and WebKit. The native browser
benchmark measures a median of 0.8 ms for 50 float actions (five batches) on
the local machine. The reference Phoenix bundle grows from 53,539 to 54,050
gzip bytes relative to the pre-float commit. The integer benchmark uses a
different template and is not an isolated cost comparison.

Arithmetic that produces a nonfinite JavaScript number fails before a result
is committed. The Elixir handler also raises for arithmetic overflow. These
tests establish the published finite float subset; they do not make `Decimal`
structs or arbitrary numeric Elixir functions client compatible.
