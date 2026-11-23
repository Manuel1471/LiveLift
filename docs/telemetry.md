# Measuring native events before and after migration

## Existing LiveLift wrapper

An opted-in LiveComponent emits one server-side `[:live_lift, :component, :event]`
measurement for every event handled by the LiveLift wrapper. Its measurements
contain `duration` in native monotonic time units. Metadata contains
`component`, `event`, `marked?`, and `outcome` (`:ok`, `:duplicate`, `:gap`, or `:error`).
Neither event parameters nor state values are recorded.

```elixir
:telemetry.attach(
  "my-live-lift-events",
  [:live_lift, :component, :event],
  fn _name, %{duration: duration}, metadata, _config ->
    milliseconds = System.convert_time_unit(duration, :native, :microsecond) / 1_000
    MyApp.Metrics.observe(metadata.component, metadata.event, metadata.marked?,
      metadata.outcome, milliseconds)
  end,
  nil
)
```

Count events by component and event to find frequent interactions. Compare the
server duration with browser interaction measurements before choosing a handler
to migrate. The measurement covers the handler and LiveLift's authoritative
reply preparation; it does not include network latency, browser rendering, or
time spent in telemetry handlers. Telemetry handlers run synchronously, so keep
them short. The wrapper also records unmarked events on the same component,
which gives a local server baseline. This event does not instrument components
that have not opted into `use LiveLift`.

## Baseline before migration

Use Phoenix's native stop spans to count completed events and measure the
same server span before and after opt-in. Phoenix provides these spans on
existing LiveViews and LiveComponents. Select safe metadata instead of
forwarding the span's full metadata.

```elixir
:telemetry.attach_many(
  "my-phoenix-event-baseline",
  [
    [:phoenix, :live_component, :handle_event, :stop],
    [:phoenix, :live_view, :handle_event, :stop]
  ],
  fn
    [:phoenix, :live_component, :handle_event, :stop],
    %{duration: duration}, %{component: module, event: "inc"}, _ ->
      MyApp.Metrics.observe_native_event(module, "inc", duration)

    [:phoenix, :live_view, :handle_event, :stop],
    %{duration: duration}, %{socket: %{view: module}, event: "inc"}, _ ->
      MyApp.Metrics.observe_native_event(module, "inc", duration)

    _, _, _, _ ->
      :ok
  end,
  nil
)
```

The app's observer should increment a counter and record duration in
native time units, or convert it at the metrics boundary. Use an allowlist
of the events and modules you want to compare. Identify the deployment or
mode from app configuration. LiveLift's wrapper event overlaps Phoenix's
span, so use a separate metric for its duration and outcomes.

A local measurement of Phoenix's server span for the counter fixture
uses `LiveViewTest` to interleave 100 increments per variant after 20
warmups:

```sh
cd examples/demo
LIVE_LIFT_BENCH=1 mix test test/live_lift_demo_web/live/event_telemetry_test.exs --only telemetry_benchmark
```

## Browser comparison

Measure when the interaction changes the DOM and when the server
acknowledges it. The two times can differ with `@client true`. In the
server-only counter, the DOM update is the point where the server result
is observed.

```sh
cd bench
LIVE_LIFT_BENCH=1 npm run e2e -- --project=chromium --grep 'benchmark native component click latency'
```

The [browser probe](https://github.com/Manuel1471/LiveLift/blob/main/bench/e2e/support.mjs) starts the clock just before
dispatching the click in the page. It watches the counter's DOM and the
optimistic acknowledgment, and returns only elapsed times. For each CPU
profile, the benchmark discards five warmups per variant and interleaves
100 measurements per variant with alternating order. It runs in a fresh
Chromium process with 1x and 4x CPU settings and 75 ms of configured
LiveSocket latency simulation. Output includes min, median, p95, max and
interquartile range in milliseconds. This measures DOM availability and
acknowledgment on the fixture. It leaves browser timing collection out
of the application runtime.

Use the server event counts to choose a frequent, supported candidate.
Compare the server duration, DOM update and acknowledgment under the
same workload before deciding whether the local prediction is worthwhile.
