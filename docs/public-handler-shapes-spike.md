# Handler shapes in public LiveView applications

## Question

Would accepting common batches of assigns and simple local bindings
let existing LiveView components opt in with fewer changes?

## Method

Use the [same pinned 12 repositories and source directories](../bench/public_apps.tsv)
as the [public audit](public-app-audit-spike.md). On 2026-11-25, run from
LiveLift `e0e241e` on macOS arm64 with Elixir 1.20.2, OTP 29.0.3 and
LiveView 1.2.15. Instrument a temporary copy of the auditor to classify
the AST for the 862 E055 results caused by the return or update shape.
Group plain identifier bindings separately from blocks containing other
statements. Normalize a final piped call to the equivalent direct call
for counting.

Run two compiler variants in an isolated Mix process. The first lowers
`assign(socket, pairs)` with a literal keyword list or map of unique
atom keys to a shallow merge with the original state. The second also
lowers blocks of simple, distinct local bindings followed by a supported
return to nested single-branch `case` expressions. Both reuse the current
expression compiler. Run each variant with the complete template check
and with the handler-only probe from the original audit.

## Result

Of the 862 clauses, 63 single-expression handlers ended with literal
`assign/2`. Another 73 ended with literal `assign/2` or `assign/3` after
simple identifier bindings. These are syntactic counts. The expressions
inside a binding or assignment can still require server functions.

| Compiler in the experiment | Handler step only | Handler and template |
| --- | ---: | ---: |
| Current compiler | 33 / 1,562 | 0 / 1,562 |
| Literal `assign/2` | 77 / 1,562 | 0 / 1,562 |
| Literal `assign/2` and simple local bindings | 90 / 1,562 | 0 / 1,562 |

Of the 33 original handler candidates, 13 hit a generic HTML tag error
at an EEx expression, 11 lacked a literal render, one lacked a keyed
repeated element, four used remote function components, two used an
unsupported click command and two used string interpolation in a binding.

## Limits

Compiler acceptance in the spike measures static shape only. Before
shipping either lowering, verify expression evaluation order, assign-key
restrictions, missing initial fields, variable scope and real DOM updates
against Phoenix. The prototype was confined to scratch files.

## Decision

Prioritize the template path for a measured migration. Report existing EEx
body blocks as a client subset limitation, with alternatives using
`{...}`, `:if` and keyed `:for`. Keep the prototype measurements as
evidence for the next handler-language decision.

## Diagnostic verification

The pinned corpus reproduced all 1,562 results after the diagnostic change.
Thirteen results moved from E065 to E061. The new message identifies EEx
at the opening delimiter and shows the supported template alternatives.
An unclosed delimiter still gives E065. Tests cover direct bindings, control
blocks, and EEx inside HTML comments, including an escaped opener.

```sh
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
python3 bench/audit_public_apps.py
```

On 2026-11-25, both parser paths passed 159 tests on LiveView 1.2.15.
A clean comparison checkout pinned to LiveView 1.2.0 passed the 16
parser and template property tests. The generated rejection corpus
covers 160 source placements on both parser paths.
