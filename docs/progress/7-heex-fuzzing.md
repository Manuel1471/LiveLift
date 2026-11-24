# Phase 7 — Generated native HEEx coverage

The [property test](../../test/live_lift/template_property_parity_test.exs)
crosses 13 native HEEx fragments with 80 state and nesting variations
from seed `20261124`. The fragments exercise escaped scalar bindings,
conditional classes and attributes, keyed loops, local components with
props and a default slot, native click targets and parameters, focus,
class and dispatch commands, debounced form changes, nested fields,
draft scopes, and Boolean attributes.

Each case compares the two parser outputs after compilation. It also
compares the DOM parsed from LiveLift's Elixir-rendered HTML with the DOM
created by the browser hook in LinkeDOM. The native browser suites exercise
the actual Phoenix render and browser path for commands and drafts.

The first run exposed a mismatch in the Elixir renderer. A compiled
`phx-click` command includes quotes in its JSON value. Directly
interpolating the value into a quoted HTML attribute truncated it and
created a malformed attribute. The serializer now escapes literal
quotes while preserving entities already present in the template.
The compiler output and JavaScript runtime use the same representation.

Seed `20261125` gives 16 source offsets and generated nests for eight
rejected forms. Both parsers preserve the expected diagnostic code and
exact source line for all 128 cases. The rejection corpus covers malformed
markup, loops without identity, unsupported expression attributes, remote
components, invalid event targeting, repeated form names, draft placement,
and unsupported native commands.

## Reproduce

```sh
mix test test/live_lift/template_property_parity_test.exs
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test \
  test/live_lift/template_property_parity_test.exs test/live_lift/parser_test.exs
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/js_commands_spike.spec.mjs e2e/form_drafts.spec.mjs
```

On 2026-11-24, the checks ran against baseline `e6244e1` with the changes
in this delivery on macOS 26.5.2 (Apple M4), Elixir 1.20.2, OTP 29, and Node
26.5.0. The library passed 150 tests. Nine focused checks passed with the
fallback forced. A temporary checkout pinned to LiveView 1.2.0 passed
all three property tests. The 21 browser checks passed with deployed
assets in Chromium 158.0.8127.18, Firefox 159.0 and WebKit 27.2.

This covers the listed native forms. Arbitrary HEEx and external review
remain open.

## Composed templates and state transitions

The second corpus combines four templates with 64 samples from seed
`20261126`. It covers nested keyed lists with conditions, local components
and default slots inside rows, nested submitted field names and per-row
draft scopes, sibling loops with the same keys, and marked clicks alongside
native JS commands. Both parsers produce the same compiled tree.

Each case starts from Elixir-rendered markup. The JavaScript hook then
reorders and edits rows, hides content and removes rows, and restores
previously removed content. All 1,024 DOM updates are compared with a
fresh render for the corresponding state. These cases drive the DOM
reconciler directly. Browser integration tests cover LiveView transport.

The corpus exposed a test harness issue with textarea text. LinkeDOM
leaves HTML character references literal there, so the harness decodes
them once when reading server HTML. A separate probe confirmed the same
single-decode behavior in Chromium, Firefox, and WebKit. The LiveLift
runtime remains unchanged.

On 2026-11-24, against baseline `e3b0207` with this corpus, the full
suite passed 151 tests and all four property tests passed with the
fallback forced. A focused deployed-assets run passed nine checks
covering keyed focus, server/client DOM parity, and state isolation
in Chromium 158.0.8127.18, Firefox 159.0, and WebKit 27.2. The local
toolchain and machine matched the first run.

```sh
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test test/live_lift/template_property_parity_test.exs
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/live_lift.spec.mjs \
  --grep 'focused keyed input|100 opted-in islands|server HTML and client render'
```

## Comparison with Phoenix HEEx

Five templates each run over 64 states from seed `20261127`. The test
compiles the same source through Phoenix's `~H` macro and the LiveLift
template compiler, with identical local component definitions. It mounts
the hook on HTML produced by Phoenix and compares the rebuilt DOM to
Phoenix's render. A second state changes text, Boolean attributes,
visibility and list order, and the hook reconciles the existing DOM.
The test compares that result to a new Phoenix render of the second state.

All 640 comparisons preserve visible text, application attributes,
LiveView event bindings, IDs and node order. The Phoenix comparison
excludes five LiveLift bookkeeping attributes. A separate comparison
checks those attributes against the LiveLift Elixir renderer. The cases
include keyed lists, props and default slots, escaping, conditional class
lists, nested form fields, draft scopes, and native JS commands.

On 2026-11-24, using baseline `676da96` and the same local toolchain,
`mix test` passed 152 tests on LiveView 1.2.15. The five property tests
also passed with the fallback forced and in a temporary checkout pinned
to LiveView 1.2.0. The deployed-asset run for JS commands and form drafts
passed 21 checks across Chromium, Firefox, and WebKit.
