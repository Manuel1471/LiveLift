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

This adds coverage of the listed native forms. It leaves arbitrary HEEx,
broader combinations of nested features, and external review open.
