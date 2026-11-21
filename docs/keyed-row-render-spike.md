# Keyed row render spike

The native list benchmark reverses and sorts 1,000 rows in Chromium. For
each action it measures 25 local predictions while disconnected and checks
that the original input node survives. A separate reversal counts calls to
`document.createElement` without including the instrumentation in the timings.

| Measurement | Baseline | With row references |
| --- | ---: | ---: |
| Elements created per reversal | 1,020 | 20 |
| Reversal median | 11.2 ms | 8.4 ms |
| Reversal p95 | 17.4 ms | 13.3 ms |
| Sort median | 11.5 ms | 8.7 ms |
| Sort p95 | 19.5 ms | 15.1 ms |

Each unchanged row previously allocated a stand-in element with two
attributes. A comment marker can carry the existing row's reference into
reconciliation. The reconciler verifies the parent and moves the row
without patching its descendants. The marker stays detached from the live DOM.

Run from `bench/`:

```sh
LIVE_LIFT_BENCH=1 npx playwright test e2e/performance.spec.mjs --project=chromium -g '1,000 native LiveComponent row'
```

The measurements cover these two unchanged-row operations on this machine.
They do not establish the budget for row content edits, large mounts, or
arbitrary templates.
