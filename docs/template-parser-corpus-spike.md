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

## Follow-up on function component props

Several public templates use ordinary Phoenix props such as `autofocus?`
and `footer?`. The adapter recognized the names, but the fallback stopped
at the attribute and reported `E065`. In an opted-in local function call,
LiveLift's compiler also rejected these names after parsing.

Both paths now accept one trailing `?` or `!` in local function prop names.
Remote function components still report `E062` in native templates. The
comparison checks a local component with both suffixes, verifies equal
compiled trees, and confirms that `constructor` is still rejected. These
prop names are expanded inside the compiler and are not emitted as HTML
attribute names.

On 2026-11-25, rerunning the same corpus with LiveView 1.2.15 reduced
different rejection codes from **99 to 20**. Identical rejections rose
from 2,550 to 2,629. All 158 compiled trees still matched. The public
component-and-handler audit still found 0 of 1,562 candidates.

The library suite passed 170 tests with each parser on LiveView 1.2.15.
The parser suite also passed 12 tests with LiveView 1.2.0 using the updated
compiler and fallback. The demo form uses `invalid?={@invalid}` in a
local function component. With deployed assets, both parser paths passed
the validation and delayed-mount checks in Chromium, Firefox, and WebKit:

```sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- --grep 'native form validates a nested field|native form validation reaches Phoenix before'
(cd ../examples/demo && LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix compile --force)
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 npm run e2e -- --grep 'native form validates a nested field|native form validation reaches Phoenix before'
```

## Follow-up on function components named like HTML controls

The adapter represents `<.input>` as a local component named `input`.
The fallback retains its leading dot. The native compiler previously
used the spelling alone when validating `phx-debounce` and other form
attributes. On `<.input phx-debounce="blur" />`, the paths could reach
different diagnostics. Marked bindings and `phx-target` conversion
could also treat component props like attributes of an HTML element.

The compiler now uses the node kind before applying those HTML rules.
Both paths keep function component call props intact for prop validation.
Tests cover self-closing and paired function tags, a rejected HTML binding
on a component call, and a genuine input rendered by the function.

On 2026-11-25, the pinned audit found 2,638 matching rejection codes and
11 different codes, down from 20. The 158 compiled trees still matched.
Ten remaining cases use Alpine's `@event` shorthand and one contains a
standalone `)` in an attribute list. The fallback rejects those names
while the LiveView path can reach a later compiler diagnostic. All eleven
templates remain rejected by both paths.

The library passed 171 tests with each parser on LiveView 1.2.15. The
parser suite passed 13 tests on 1.2.0. The demo passed nine tests,
57 handler parity cases, and both asset builds. The focused Playwright
selection passed nine checks with each parser. It covers validation, blur,
and submit cancellation in Chromium, Firefox, and WebKit with digested assets:

```sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- --grep 'native form validates a nested field|phx-debounce delays|submit cancels'
(cd ../examples/demo && LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix compile --force)
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 npm run e2e -- --grep 'native form validates a nested field|phx-debounce delays|submit cancels'
```

## Follow-up on attribute names

Reducing the remaining eleven templates to individual attributes showed that
the adapter accepted names such as `@click` and `)`, while the fallback
rejected them. A Playwright probe compared `DOMParser` and `setAttribute`
for `@click`, `)`, `1x`, `x-on:click`, and `data-item` on a new button.
Chromium 158, Firefox 159, and WebKit 27.2 accepted all five. The
[DOM standard change](https://github.com/whatwg/dom/pull/1079) explains
the wider syntax. Historical browser versions were outside this probe.

LiveLift now uses the fallback grammar for both paths. The regression test
checks the diagnostic code and column for unsupported names and equal trees
for `x-on:click` and `data-item`. Existing malformed markup still reports
`E065`. See the [attribute-name decision](decisions/ADR-0010-portable-attribute-names.md).

On 2026-11-25, the audit matched the compiled trees for 158 public
templates and the first rejection codes for the other 2,649. The demo
comparison matched all 40 outcomes. ExUnit passed 172 tests with each
parser on LiveView 1.2.15 and the focused parser suite passed 14 tests
on LiveView 1.2.0. The demo passed nine tests, 57 handler parity cases,
and both asset builds. The deployed asset run passed six focused checks
for form validation and native class commands across the three browsers.
This corpus does not establish coverage of every HEEx form or support
for every component in the source projects.
