# Event parameter reads

## Question

Do native bracket reads, `Map.get/2`, and handler map patterns agree when
an event omits a field?

## Observation

On baseline `2ef5dd6`, the compiler lowered all three to a strict field
read in JavaScript. With Elixir 1.20.2 and OTP 29.0.3, probing the same
maps gave:

| Input | `params["profile"]["name"]` | `Map.get(Map.get(params, "profile"), "name")` |
| --- | --- | --- |
| Missing `profile` | `nil` | Raises |
| Map with missing `name` | `nil` | `nil` |
| String where a map is expected | Raises | Raises |
| Present empty string | Empty string | Empty string |

Map patterns require every key in the pattern. In a mixed chain, each
read uses the semantics of that operation.

## Decision

Keep each operation in the compiler's internal form. Allow bracket
reads to propagate `nil` and keep `Map.get/2` strict about the receiver
being a map. Keep map pattern bindings strict. Verify the comparison
with Phoenix's real handler and the generated JavaScript, including
missing intermediate values and errors. Verify the demo's optimistic
render when the same button event omits its value.

## Verification

The parity test checks 25 combinations against the real Phoenix
handler and generated JavaScript, including a required pattern whose
binding the handler ignores. Tests also verify that the local-action
compiler detects shared writes inside a patterned handler. On
2026-11-25, 164 Mix tests passed with each parser on LiveView 1.2.15
and 44 component and audit tests passed on LiveView 1.2.0. The demo
passed nine Mix tests and 57 handler parity cases.

```sh
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/live_lift.spec.mjs \
  --grep 'a normal LiveComponent runs a marked handler|native phx-change and phx-submit'
```

Chromium, Firefox and WebKit passed the deployed label and form
scenarios with each parser, for 12 passes. The demo's Clear label
button sends the same event as Set label
without a label parameter. The optimistic DOM renders an empty label
before the server round trip and the confirmed snapshot contains
`null`. The shared hook measured 8,189 gzip bytes under its 8,192-byte
budget.
