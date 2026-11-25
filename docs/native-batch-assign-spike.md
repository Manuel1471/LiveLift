# Native batch assign spike

## Question

Can the native compiler accept Phoenix's literal `assign/2` without
requiring apps to split it into several socket updates?

## Method

Replay the existing handler-shape prototype on baseline `714925b`
with the colocated-template audit enabled. Compare Phoenix `assign/2`
with the generated JavaScript using literal keyword lists and maps,
an initially absent field, and expressions that read the original
socket after an earlier pipe step. Check that the compiler retains
each written field in the authoritative snapshot and in the
`@client :local` conflict check.

## Result and decision

The earlier [handler shape spike](public-handler-shapes-spike.md)
measured 44 additional handler candidates for literal batches. The
replay with colocated templates still had zero full candidates.
Phoenix can add fields that the initial socket does not contain.
The existing JavaScript map-update operation requires preexisting
keys, so a literal batch uses the existing map merge operation.
Record its written keys separately for snapshot projection and
local action isolation.

Accept literal maps and keyword lists with distinct, safe atom keys
and supported values. Preserve the original socket reads and the
existing state and event validation. Dynamic collections, callbacks,
duplicate keys and reserved assigns get a source diagnostic. The
initial snapshot may omit an assign introduced by the batch. The
template may read it after it has been initialized.

## Verification

On 2026-11-25, LiveView 1.2.15 passed 163 tests with each parser and
LiveView 1.2.0 passed the 43 component and audit tests. The parity test
uses Phoenix's authoritative handler and the generated JavaScript with
the same assigned values, including an empty string, `false` and `nil`.
It checks that a later batch reads the original socket after a prior
update. Rejection tests cover dynamic values for the entire batch,
invalid keys, duplicate keys, and a local action that would share a
field with a synchronized batch.

The demo passed nine Mix tests, 56 handler parity cases and the deployed
browser case in Chromium, Firefox and WebKit with each parser. The browser case checks
that the initial snapshot omits the draft status, that the batch renders
it before the server acknowledgment, and that the server includes it
in its reply.

```sh
mix test
LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 mix test
python3 bench/audit_public_apps.py
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/live_lift.spec.mjs \
  --grep 'native assign_new and batch assign'
```

The 1,562-clause corpus produced 51 fewer E055 results as the auditor
advanced to later checks. Full migration candidates stayed at zero.

## Generated code measurement

On macOS 26.5.2 arm64, Elixir 1.20.2, OTP 29.0.3 and Node 26.5.0,
generate two handlers that increment a count and set a label and a
boolean on the same three initialized fields. Assert equal outputs.
Warm up each JavaScript function with 50,000 iterations, then measure
nine interleaved samples of 200,000 calls per function, passing each
result into the next call. Measure raw function source with
`Buffer.byteLength(action.toString())`.

| Form | Function bytes | Median time | Sample range |
| --- | ---: | ---: | ---: |
| One literal `assign/2` | 138 | 11.08 ms | 10.86–11.50 ms |
| Three piped `assign/3` calls | 183 | 23.68 ms | 23.23–23.78 ms |

This isolates generated action evaluation in Node. The shared browser
hook measured 8,189 gzip bytes of the existing 8,192-byte budget.

## Limits

This is a compiler improvement for a native Phoenix call. The corpus
still needs changes around template rendering or other handler forms
before it offers a direct migration.
