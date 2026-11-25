# Colocated HEEx template spike

## Question

Can LiveLift compile the sibling `.html.heex` file Phoenix already uses
for a LiveView or LiveComponent, while Phoenix keeps rendering the initial
HTML?

## Method and result

On baseline `6d51625`, compile a fresh routed LiveView and a stateful
LiveComponent without explicit `render/1` functions. Put each module's
conventional `.html.heex` file next to its Elixir source and record the
`@on_definition` and `@before_compile` callbacks. Use Elixir 1.20.2,
OTP 29.0.3 and LiveView 1.2.15. Compare the hook in the LiveView 1.2.0
package.

On both Phoenix component paths, LiveView defines `render/1` before
LiveLift's hook runs. The callback reports the actual HEEx filename and
line 1. Phoenix tracks the file as an external resource. LiveLift had
been discarding the callback's file and expecting the generated body
to contain a literal `~H` sigil.

The pinned public audit found 10 clauses without an explicit render
and with a matching sibling template. Among the original 33
handler-only candidates, the 11 missing a literal render instead
used explicit functions. Those functions delegate rendering or prepare
assigns before the sigil.

## Decision

Use the source of the confirmed Phoenix-generated render and Phoenix's
normal external-resource dependency. Keep the existing supported HEEx
subset, diagnostics, and opt-in marks. The audit will look for the same
sibling when the module has no explicit render. Verify both component
types, source maps, and a real browser update after the initial render.

This probe covers Phoenix's automatic basename convention. Delegated
rendering, arbitrary template patterns and rendering functions require
separate design work.

## Verification

On 2026-11-25 the full suite passed 161 tests on LiveView 1.2.15 with
each parser. A separate checkout pinned to LiveView 1.2.0 passed 41
component and audit tests. The tests cover Phoenix's initial render
for both module kinds, source-map entries from the same generated line
that point to the HEEx file and handler source, and audit diagnostics
that use the template filename.

The demo's optional-state component now uses its colocated file. Its
nine tests and 56 handler parity cases passed. The deployed browser
case passed in Chromium, Firefox and WebKit with each parser. Editing
only the template in a scratch checkout and running `mix assets.build`
rebuilt its generated view chunk.

```sh
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
python3 bench/audit_public_apps.py
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/live_lift.spec.mjs \
  --grep 'native assign_new reveals'
```

The 1,562-clause corpus moved ten results from E060 to E055. All ten
had conventional sibling templates, and the auditor reached and
rejected their handler shapes. The number compatible end to end
remained zero.
