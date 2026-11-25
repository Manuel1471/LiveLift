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

## Attribute syntax and diagnostics

The lexer probe found that the fallback accepted unquoted attribute values,
a bare carriage return between attributes, and a closing brace in a quoted
expression where the Phoenix tokenizer required an escape. It now uses the
same whitespace and interpolation rules for these cases. Both paths also
compile bare HTML attributes such as `disabled` and `required`.

Previously, an attribute spread or the `phx-no-curly-interpolation`
directive could raise a function-clause error in the compiler. They now
produce `E061` with the original line and a correction. The fallback
recognizes the spread token so it can report the same diagnostic.

The regression tests compare 24 valid forms that vary quote style,
whitespace, line endings and spacing around `=`. They verify the literal
brace and the escaping of the resulting title. Five rejected forms are
checked through both parsers for the expected code and source line.
The Phoenix HEEx comparison also includes a static `required` field.
The probe also observed different handling of document declarations such
as `<!doctype html>`. The next check addressed that case.

```sh
mix test test/live_lift/parser_test.exs test/live_lift/template_property_parity_test.exs
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 LIVE_LIFT_CONSUMER_BROWSER_PORT=4050 \
  sh test/integration/phoenix_consumer.sh
```

On 2026-11-24, baseline `de42d17` plus this change passed 154 library
tests on LiveView 1.2.15 with each parser. The 13 parser and template
property tests passed in a separate checkout on LiveView 1.2.0. The
demo passed its nine tests and 56 handler parity cases with the
fallback forced. The fresh consumer passed migration, asset builds,
and browser checks in Chromium, Firefox, and WebKit with the fallback
forced. This used the same local toolchain as the prior runs.

## Document declarations and literal markup

A Phoenix layout owns the document declaration. The Phoenix tokenizer
returns a doctype as text without its location, whereas the fallback
previously rejected it as a tag name. Both parser paths now report
`E061` at the start of the declaration and point to the root layout.
The adapter uses the fallback to locate the declaration when it finds
one in a Phoenix text token.

The check covers lower- and upper-case declarations before markup, after
a comment and CRLF, and within an element. An HTML comment containing
the same words remains a comment. The independent Phoenix comparison
also verifies that literal braces and text around an HTML comment have
the same visible DOM after LiveLift renders.

On 2026-11-24, baseline `208a770` plus this change passed all 155 tests
with the default parser and with the fallback forced on LiveView 1.2.15.
The 14 parser and template property tests passed in a checkout pinned to
LiveView 1.2.0. The fresh Phoenix consumer again passed migration, both
asset builds, and the Chromium, Firefox, and WebKit checks. See the
preceding section for the consumer command and environment.

## Server-side HEEx comments

The [comment spike](../heex-comments-spike.md) found that the native
tokenizer could leave separately compiled text fragments after removing
a server-side comment. The adapter now rejoins adjacent text, including
split HTML comments. The fallback consumes the comment without emitting it.
Both paths check the source coordinates after a multiline comment and
report `E065` at the opening delimiter when the closing marker is missing.

A sixth template adds 128 comparisons to the Phoenix oracle, bringing
the total to 768. It rebuilds and updates conditional content with comments
inside both visible text and HTML comments. The test in a real browser
verifies the same accessible button name before and after a marked
optimistic update using the demo's deployed assets.

```sh
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
# Run in a scratch checkout with the matching Mix dependencies.
LIVE_LIFT_LIVE_VIEW_VERSION='== 1.2.0' mix test \
  test/live_lift/parser_test.exs test/live_lift/template_property_parity_test.exs
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- \
  e2e/live_lift.spec.mjs --grep 'a normal LiveComponent runs a marked handler'
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 npm run e2e -- \
  e2e/live_lift.spec.mjs --grep 'a normal LiveComponent runs a marked handler'
```

On 2026-11-25 against baseline `243c703`, 158 Mix tests passed under
each parser on LiveView 1.2.15, and the 15 focused tests passed on
LiveView 1.2.0. Both parser paths passed in Chromium 158.0.8127.18,
Firefox 159.0 and WebKit 27.2. The runs used macOS 26.5.2 arm64,
Elixir 1.20.2, OTP 29.0.3 and Node 26.5.0. The shared runtime measured
8,189 gzip bytes against the existing 8,192-byte budget.

## Direct form controls and component boundaries

The rejection corpus exposed a difference between self-closing controls
and controls with closing tags. Direct marked changes on a `textarea`
with a nested name or a multiple `select` compiled without a diagnostic.
Both parsers now return `E063` at the control. The positive cases compile
a marked single select and a marked textarea with flat names. They also
compare the unmarked multiple select against Phoenix's rendered binding.

The expanded rejection corpus runs 19 shapes through 16 generated
nesting and source-offset variations. Each of the 304 cases checks both
parsers. The added samples cover named slots, directives on component
calls, encoded static props, form name conflicts, arrays, reserved
parameter segments, radio controls, and direct changes on textareas and
selects. The independent renderer adds 384 comparisons for scalar
attributes, select/option markup, and nested component calls and slots,
for 1,152 Phoenix comparisons in total.

```sh
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
# Use a scratch checkout locked to LiveView 1.2.0 for this command.
LIVE_LIFT_LIVE_VIEW_VERSION='== 1.2.0' mix test \
  test/live_lift/parser_test.exs test/live_lift/template_property_parity_test.exs
cd bench
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 npm run e2e -- \
  e2e/live_lift.spec.mjs e2e/form_drafts.spec.mjs \
  --grep 'phx-change and phx-submit|phx-debounce delays|submit cancels|persists through reload'
```

These samples cover selected forms and compile-time diagnostics. The
independent oracle compares DOM and binding attributes. The deployed
browser checks exercise native form submission, debounce and drafts.

Against baseline `d85fe6a`, the 165 library tests passed with both parser
configurations on LiveView 1.2.15. The 16 focused tests passed on LiveView
1.2.0. The 12 deployed browser checks passed in Chromium 158.0.8127.18,
Firefox 159.0 and WebKit 27.2. The runs used Elixir 1.20.2, OTP 29.0.3 and
Node 26.5.0 on macOS arm64. A fresh Phoenix consumer passed migration and
both asset builds with the fallback forced. The shared hook measured
8,192 gzip bytes.

## Forms after component expansion

The spike asked whether a form gets the same validation when local
components or slots supply its fields. A form with two calls to a field
component compiled even though both calls rendered `profile[note]`.
The original validation ran before expansion and could only inspect
fields declared directly in the same template.

Both parsers now reject duplicate names, conflicting map paths,
unsupported controls and direct marked changes across these boundaries.
The rejection tests cover a form inside a component and a component
inside a form. They check the diagnostic against the source file and
line of the form. The expanded client tree omits the source-file metadata
used only for validation. Supported nested fields and unmarked form
handlers still compile.

The native form in the demo now renders its draft field through the
default slot of a local component. The browser checks exercise validation,
submission, and draft recovery on that path. The checks cover the
documented static field names and local component subset.

```sh
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
sh test/integration/phoenix_consumer.sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/live_lift.spec.mjs e2e/form_drafts.spec.mjs \
  --grep 'phx-change and phx-submit|validates a nested field|opt-in draft'
```

Repeat the browser command with `LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1` to
exercise the alternate parser. Against baseline `4a24cf3`, the library
passed 166 tests per parser configuration on LiveView 1.2.15. The 17
focused parser and template tests passed in a checkout locked to
LiveView 1.2.0. The demo passed nine tests and 57 handler parity cases.
The browser checks passed 18 times per parser across Chromium, Firefox
and WebKit with deployed assets. A fresh Phoenix consumer passed migration
and both asset builds. The shared browser hook measured 8,192 gzip bytes.
