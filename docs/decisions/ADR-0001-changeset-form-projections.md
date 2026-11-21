# ADR-0001 — Project native changeset form values

Status — accepted for the 5.2 compiler work.

## Context

The [form spike](../changeset-form-spike.md) showed that Phoenix's displayed
value can differ from the cast change. The browser needs both semantics
alongside the native error order and the form action.

## Options

- Serialize `Ecto.Changeset` and `Phoenix.HTML.Form` structs. Apps could keep a
  single assign, but this expands the wire contract and makes implementation
  details part of browser state.
- Introduce a LiveLift-specific form API. This makes the projection explicit
  but adds a new form concept for apps to learn.
- Compile supported reads from the native form. Apps keep their Ecto pipeline
  and choose which values belong in browser state.

## Decision

Compile native reads of the displayed value, input usage, and projected error
tuples. Use the already supported string changeset operations to recover the
displayed value and error order. Keep messages and the numeric count available
to the application's callback. Unused fields use Phoenix's existing parameter
convention. Limit this change to reading that metadata. Generation of metadata
from DOM interactions and a complete form demo remain follow-up work in 5.2.

## Evidence

The [Elixir/Node corpus](../../bench/changeset_parity.exs) and
[browser corpus](../../bench/e2e/changeset_parity.spec.mjs) compare the results
with Ecto and Phoenix. [E052](../errors/E052.md) records the compiler boundary.
