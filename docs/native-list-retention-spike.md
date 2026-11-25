# Native list retention spike

## Question

Do a native island and its listeners survive when LiveView navigates
away after repeated keyed row updates?

## Method

Use the demo with production assets. In one Chromium document, navigate
between the server counter and a native list with 1,000 rows. Reverse
the list and wait for the authoritative acknowledgment before each
navigation. Force collection between measurements. Check the detached
island directly for listeners and check whether weak references to it
and representative rows clear. Compare DOM, listener and JavaScript
heap counters after warmup and after repeated visits.

Use Chromium's
[DOM counters](https://chromedevtools.github.io/devtools-protocol/tot/Memory/#method-getDOMCounters),
[heap usage](https://chromedevtools.github.io/devtools-protocol/tot/Runtime/#method-getHeapUsage)
and [garbage collection](https://chromedevtools.github.io/devtools-protocol/tot/HeapProfiler/#method-collectGarbage).
Use [listener inspection](https://chromedevtools.github.io/devtools-protocol/tot/DOMDebugger/#method-getEventListeners)
on the mounted island and on the same root after it detaches. Release
the DevTools handle before each memory sample.
A full page reload would discard the measured document, so require the
same document throughout.

Run three warmup visits, then 12 measured visits with five reversals per
visit. After each group of four measured visits, wait for two render
frames and force garbage collection, twice. Compare the counters with
the server-only page sampled after warmup. Keep weak references to the
island and three representative rows per visit.

## Result

The initial spike sampled after one collection and saw an intermediate
rise from 129 to 27,285 nodes. The final sample returned to 129 and
all weak references cleared. The fixed render and collection sequence
gave stable DOM samples without changing the limits.

On 2026-11-25, three repetitions on source baseline `91060ae` passed
with Chromium 158.0.8127.18, Node 26.5.0, Elixir 1.20.2 and OTP 29.0.3
on macOS arm64. Each sampled point had 129 nodes, 72 listeners and the
same document count as the warmup sample. Every detached island had zero
listeners and all 60 weak references cleared in each repetition. The
largest heap increase above warmup was 297,116 bytes.

Two controls deliberately introduced retention in a scratch copy. Holding
one detached root kept four sampled references and failed the collection
assertion. Omitting the removal of the optimistic click listener left one
listener on the detached root and failed the teardown assertion.

The test requires zero retained sample references, zero listeners on the
detached island, and a steady document count. It allows up to 250 extra
DOM nodes, 16 extra listeners and 1 MiB of JavaScript heap for background
work and engine caches.

```sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_BENCH=1 npm run e2e -- \
  e2e/native_list_retention.spec.mjs --project chromium --repeat-each 3
```

## Limits and decision

Keep this check in the opt-in Chromium benchmark suite. It measures
retention after repeated navigation on the 1,000-row demo, using CDP
document, DOM and JavaScript counters. Browser process memory, Phoenix
processes, other browser engines and different app workloads require
their own measurements.

## Cross-browser teardown

The portable check uses the same 1,000-row list and five confirmed
reversals per visit. It tracks persistent listener registrations on the
list root through the DOM methods. Listener identity follows the event
type, callback and capture flag. The tracker uses a `WeakMap` and holds
each island only until its teardown assertion.
[DOM event listener rules](https://dom.spec.whatwg.org/#concept-event-listener).

One warmup visit supplies the mounted listener count and the number of
connected elements under `main` on the server page. Six more visits in
the same document must match both counts. Every detached island must
have zero registrations. The check runs with digested assets in CI.
The opt-in Chromium benchmark separately measures heap usage and weak
references to detached rows. The portable check only measures listener
teardown and connected elements in the app content.

```sh
cd bench
LIVE_LIFT_TEST_DEPLOY=1 npm run e2e -- e2e/native_list_retention.spec.mjs --grep 'release listeners'
LIVE_LIFT_TEST_DEPLOY=1 LIVE_LIFT_FORCE_TEMPLATE_FALLBACK=1 npm run e2e -- \
  e2e/native_list_retention.spec.mjs --grep 'release listeners'
```

Against baseline `8442429`, the portable check passed with each parser
configuration in Chromium, Firefox and WebKit. The repeated Chromium
heap check again measured 129 DOM nodes, 72 listeners and zero retained
sampled references at every collected point. The largest heap increase
over warmup was 289,816 bytes.

Omitting one click listener removal in a scratch build caused WebKit to
report one registration on the detached island. The verified runtime
removed it.
