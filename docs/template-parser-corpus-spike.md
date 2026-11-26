# LiveView parser compatibility on real templates

For LiveLift maintainers testing the 0.1 release line.

## Question

Do the LiveView parser adapter and the fallback compile the same HEEx when
given actual templates from the demo and public Phoenix applications?

## Method

From the repository root, run:

```sh
mix run bench/compare_template_parsers.exs demo examples/demo/lib
python3 bench/audit_public_apps.py
```

The second command fetches the twelve revisions listed in
[`bench/public_apps.tsv`](../bench/public_apps.tsv). The probe reads `.heex`
files and extracts literal `~H` bodies from the AST of `.ex` files. It skips
symlinks and does not evaluate application code. It feeds each template into
the adapter and fallback, then runs the native tree compiler with an empty
set of marked handlers and local component definitions. It compares the
compiled trees or the first diagnostic code. The adapter can use its usual
fallback when upstream returns nodes it cannot translate.

## Result

Run on Apple M4 with Elixir 1.20.2 and OTP 29.0.3, using the demo and
compiler from `366075e` with the probe added on 2026-11-25.

| Corpus | Templates | Same compiled tree | Same rejection code | Different rejection code | Compilation mismatch |
| --- | ---: | ---: | ---: | ---: | ---: |
| Demo, LiveView 1.2.0 | 40 | 12 | 28 | 0 | 0 |
| Demo, LiveView 1.2.15 | 40 | 12 | 28 | 0 | 0 |
| Pinned public sources, LiveView 1.2.15 | 2,807 | 158 | 2,550 | 99 | 0 |

The audit also found zero whole-component candidates among 1,562 handler
clauses. A tree that compiles in isolation does not establish that its view
can opt in. Public repositories are source fixtures. Application context,
server-side framework components, actual handler parameters, and deployment
behavior are covered separately by the demo and consumer tests. Diagnostic
differences outside the accepted subset remain visible in the audit.

## Decision

Run the demo comparison in both pinned LiveView compatibility lanes. Run the
public comparison in the weekly source audit. Both checks fail if exactly
one parser compiles a template or if the compiled trees differ. The demo
also requires at least one successful comparison and agreement on the
first code for rejected templates.
