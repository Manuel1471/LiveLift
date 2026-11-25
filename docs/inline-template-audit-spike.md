# Inline HEEx and audit parity spike

## Question

Does converting simple EEx assign output by itself make public LiveView
handlers direct opt-in candidates, and does the source audit already agree
with the production compiler on equivalent inline HEEx?

## Method and result

On baseline `ffef6b2` with LiveView 1.2.15, replay the 12 pinned public
repositories through a scratch copy of the auditor. Before validating the
template, replace only direct assign paths such as `<%= @label %>` and
`<%= @channel.name %>` with their brace bindings. Leave joins, blocks and
function calls alone. This is a source-only experiment, without loading
any public application or changing its checkout.

All 1,562 clauses still had a blocker. In the Beacon and Algora examples
that advanced past the direct assign, later EEx constructs blocked the
same templates.

A separate fixture uses a literal `~H` render, a private local function
component, a nested local component, and a default slot. The real
compiler already collects those definitions. The audit supplied an
empty definition map and rejected the first local component call.

## Decision

Bring the static audit into parity for the existing local component
subset. Keep collecting source without loading the application code.
Share literal-sigil extraction and duplicate-definition diagnostics
with the compiler. Compare an audited source fixture to the same
module compiled with its opt-in markers. Leave the direct EEx source
conversion as an experiment because it did not yield a direct
candidate in this corpus.

## Verification

The regression test audits a nested local component with a default
slot, compiles the same module with the normal opt-in marks, and
checks diagnostics for an unknown component and duplicate definitions.
On 2026-11-25, 165 tests passed on LiveView 1.2.15 with each parser and
45 component and audit tests passed on LiveView 1.2.0. The pinned corpus
still reports zero direct candidates. Fifteen clauses now report E062
for duplicate local component definitions, the same restriction the
native compiler applies before compiling the template.

```sh
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
python3 bench/audit_public_apps.py
```

In a scratch source extraction, replace the consumer fixture's inline
`<output id="count">` with a call to a private function component that
renders the same element from its `count` prop. Run
`LIVE_LIFT_INTEGRATION_IGNITER=1 LIVE_LIFT_CONSUMER_BROWSER_PORT=4053 sh test/integration/phoenix_consumer.sh`.
The rehearsal used the local Hex package and preloaded Tailwind 4.3.3
and esbuild 0.25.4. The audit, migration, four parity cases, and both
asset builds passed. Chromium, Firefox and WebKit displayed the count
before acknowledgment and confirmed the same saved value.
