# Changelog

## Unreleased

### Added

- Compile Phoenix's automatically colocated `.html.heex` files and point
  the audit diagnostics and generated source maps to the template file.
- Compile native `assign/2` with a literal map or keyword list and include
  newly assigned fields in the authoritative snapshot.
- Include inline local function components when auditing a native
  LiveView or LiveComponent.

### Fixed

- Preserve function component props ending in `?` or `!` in both HEEx
  parser paths.
- Apply form and event binding rules to HTML elements inside function
  components. Report unsupported props at the component call.
- Accept Phoenix's native form target metadata before client mount and
  when LiveLift is disabled.
- Report view loading failures through the browser's standard error
  event and omit exception details from loading and offline replay reports.
- Escape quotes in static template attributes emitted by the Elixir renderer,
  including compiled LiveView JS commands.
- Preserve bare HTML attributes such as `disabled`. Report unsupported
  spread attributes and align the fallback parser with Phoenix's attribute
  value and brace rules.
- Point to the source location when a document declaration appears inside
  a LiveLift template. Keep declarations in the Phoenix root layout.
- Map generated native actions to their Elixir handler definitions and
  outer expression lines when available.
- Preserve Phoenix's handling of server-side HEEx comments and report
  unclosed comments at their source location with both parser paths.
- Explain unsupported EEx body expressions with source coordinates and
  the corresponding HEEx bindings or directives.
- Match Elixir's optional event parameter reads, including missing
  values in nested bracket paths.
- Show a status message when reconnecting discards expired offline actions.
- Report `E063` for marked changes on multiple-select controls and on
  direct textareas or selects with unsupported field names.
- Apply form field and event constraints across local HEEx components
  and their default slots.
- Apply marked form restrictions to mixed-case control attributes and
  report input types written with HTML character references.

## 0.1.0-rc.1

First LiveLift release candidate for Hex. Supports Phoenix LiveView 1.2.x.
The integrated startup and asset installer target the standard Phoenix 1.8
layout.

- Opt in a routed LiveView or stateful LiveComponent with `use LiveLift`.
  Use `@client true` for optimistic events confirmed by LiveView or
  `@client :local` for transient display changes. Unmarked events use
  normal LiveView handling.
- Compile a defined subset of Elixir and HEEx, including keyed lists,
  bounded forms and local function components. Report unsupported
  forms with a diagnostic code and source location.
- Reconcile server snapshots with pending predictions and preserve keyed
  row identity. Support selected Phoenix JS commands, bounded timers, and
  opt-in draft recovery for text fields.
- Install with Mix or Igniter. Generate source maps and support optional
  split view chunks and TypeScript declarations. The browser runtime ships in Hex.
- Audit candidates, compare Elixir and JavaScript handler results, inspect
  state in development, and measure event traffic and latency.

See the [Phoenix guide](docs/phoenix-integration.md), the
[adoption practices](docs/best-practices.md), and the
[production limits](docs/production-readiness.md).
