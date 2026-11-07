# Component event telemetry

An opted-in LiveComponent emits one server-side `[:live_lift, :component, :event]`
measurement for every event handled by the LiveLift wrapper. Its measurements
contain `duration` in native monotonic time units. Metadata contains
`component`, `event`, `marked?`, and `outcome` (`:ok`, `:duplicate`, or `:error`).
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
