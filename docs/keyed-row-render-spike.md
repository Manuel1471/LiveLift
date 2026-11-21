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
They do not establish the budget for large mounts or arbitrary templates.

## Row edits and authoritative snapshots

The runtime caches the state and item paths read by each keyed row template.
It reuses a row when the referenced values are equal, even if the server
decoded every item into a new object. A parent field change invalidates
rows that read that field. Nested loops use normal reconciliation.

In Chromium, 25 edits to a single input in a 1,000-row list measured
2.5 ms median and 8.3 ms p95. The test checked the final value, focus and
neighboring input identity. A separate browser test rewrites the edit
parameter at the local test server boundary to force an authoritative
correction. Across Chromium, Firefox and WebKit, it preserved the edited
and neighboring inputs and allocated at most two row elements for the
prediction and correction together.


The same analysis now skips unchanged ordinary subtrees after the first
reconciliation has associated their template with live elements. That
association lets a changing subtree keep its parent even when conditional
siblings move. Unkeyed form controls reconcile their live values and
selection, and component calls keep their own scope. The DOM regression
probe removes a sibling and changes adjacent text without creating a fresh
static descendant.


With dependency reuse outside lists, a reversal allocates two elements.
In a separate 25-sample run Chromium measured p95 of 13.5 ms for reversal,
17.7 ms for sort and 8.3 ms for a row edit. Sorting still needs tuning to
meet a 16.7 ms budget consistently.

The standalone runtime weighed 7,437 bytes after the demo's esbuild
minifier and gzip. The row-marker-only baseline was 6,984 bytes. To
measure from `examples/demo/` after building assets:

```sh
livelift_esbuild=$(mix run --no-start --no-compile -e 'IO.puts(Esbuild.bin_path())')
"$livelift_esbuild" --minify < ../../assets/js/live_lift/client_hook.js | gzip -cn | wc -c
```
