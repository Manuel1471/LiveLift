# Phase 7 — Source maps for native event handlers

On baseline `9fa54fb`, a generated view entry had one mapping, at its
module name. A lookup anywhere on that line, including in an action,
pointed to the view's `~H` sigil.

The compiler now maps the start of each generated native action to its
`handle_event/3` definition and the action body to the outer Elixir
expression's line when available. The template has its own segment on
the same generated line. Columns in the JavaScript use UTF-16 code
units, so an emoji earlier on the line cannot shift a later mapping.
Sources are embedded once per file. The timer test covers the
initiating event. Nested expressions, helpers and delayed callbacks
still lack individual segments, and the source column is the start of
the Elixir line.

Run the eager and split checks from the repository root.

```sh
mix test test/live_lift/component_test.exs
LIVE_LIFT_INTEGRATION_IGNITER=1 sh test/integration/phoenix_consumer.sh
```

The eager check decodes the map with Node, verifies both statements of
origin for a multiline handler and checks the column after an emoji
in a preceding handler. The consumer installs a local Hex package in
a generated Phoenix app, builds eager assets, and checks the split
chunk for an ordinary handler and a timed handler. It also runs
`assets.deploy` with the runtime from Hex.

The demo deployment check also resolves the counter handler through
the composed esbuild map, then checks that deployment removes public
maps and keeps the compiler maps private.

```sh
cd examples/demo
sh ../../test/integration/demo_source_maps.sh
```

On 2026-11-25, the full Mix suite passed 157 tests on Elixir 1.20.2,
OTP 29.0.3 and Node 26.5.0. The Phoenix consumer and demo checks passed
on macOS arm64 with esbuild 0.25.4. The consumer used Phoenix 1.8.16
and preloaded esbuild and Tailwind 4.3.3 before the asset tasks.
