# `Enum.sort_by/2` term-order spike

The browser cannot use JavaScript's default `sort()` order for Elixir keys.
The published client state contains safe integers, finite binary64 floats,
`nil`, booleans, atom-keyed maps, lists, and valid UTF-8 strings. We tested
their order with the local Elixir runtime before enabling `sort_by/2`.

| Probe | Elixir result | Browser consequence |
| --- | --- | --- |
| `"\uE000" < "\u{10000}"` | `true` | UTF-16 code-unit comparison gives the opposite answer; compare Unicode code points, equivalent to UTF-8 byte order for valid strings. |
| `1 <= 1.0` | `true` | Equal numeric keys must keep their input order and retain their distinct wire types. |
| `false < nil`; `nil < true` | Both `true` | Boolean and nil keys follow atom-name order. |
| `%{} < []`; `[] < ""` | Both `true` | The supported type order is number, atom, map, list, binary. |
| `%{a: 99} < %{a: 1, b: 0}` | `true` | Map size takes precedence over values. |
| `%{a: 2, b: 0} > %{a: 1, b: 99}` | `true` | Equal-sized maps compare sorted keys, then values. |

The implementation decorates each list element with its projected key and
original index. A recursive comparator handles the safe state types; the
index makes equal-key order explicit. The mapper runs once per element.
`test/live_lift/property_parity_test.exs` checks 1,000 seeded lists of mixed
types, while `test/live_lift/float_parity_test.exs` checks 302 lists containing
tagged floats, signed zero, and safe integer boundaries. The native demo
sorts app-owned rows and verifies keyed focus and server convergence in three
browsers.

The reproducible Chromium benchmark
`LIVE_LIFT_BENCH=1 npx playwright test -g 'benchmark 1,000 native LiveComponent row sorts' --project=chromium`
measured 25 local reverse-and-sort cycles of 1,000 keyed rows: median 10.9 ms,
p95 18.3 ms on this machine, with input identity preserved. The p95 exceeds a
16.7 ms frame budget; larger lists still need the phase 4 rendering work. The
reference Phoenix bundle, which does not use `sort_by`, measured 54,050 bytes
gzip with LiveLift versus 47,221 bytes without it. These figures are workload
specific and do not measure general LiveView overhead.

This does not enable arbitrary Erlang terms, custom sorters, or `Enum.sort_by/3`.
The comparator accepts only values permitted by `LiveLift.State`.
