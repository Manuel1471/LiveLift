# ADR-0002 — Compile literal LiveView focus commands

Status — accepted for the first 5.3 increment.

## Context

The [command spike](../liveview-js-spike.md) found that focus survives
reconciliation when the node survives, while an external class change
can be overwritten.

## Alternatives

- Accept encoded command JSON. This needs little compilation, but obscures
  which operations run and cannot enforce the intended allowlist.
- Introduce a second client event language. This would make timing and selector
  handling LiveLift's responsibility and change the app's template API.
- Encode a small allowlist of literal calls with the native LiveView module
  and let Phoenix execute them.

## Decision

Use the third option for native `focus` and `focus_first` click commands.
Limit targets to the source element or one of its descendants using a simple
literal relative selector. Reject computed commands and raw command JSON.
The generated registry retains the same encoded binding across renders
without adding execution code to the shared runtime. Record separate
parity evidence before extending the allowlist to persistent mutations.
