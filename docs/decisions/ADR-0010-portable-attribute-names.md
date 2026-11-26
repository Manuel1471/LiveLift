# ADR 0010 — Share the attribute name grammar across HEEx parsers

## Status

Accepted on 2026-11-25 for the experimental 0.1 release line.

## Context

The LiveView tokenizer accepts attribute names outside LiveLift's fallback
grammar. A minimized template compiled with the adapter and failed with
the fallback. The browser hook uses `setAttribute` when it creates elements,
so the two parser paths must agree on the names sent to that API.

Current Chromium, Firefox, and WebKit all accepted the minimized names.
Earlier implementations applied XML name constraints. Adopting the relaxed
rules would make the same generated template depend on a newer browser API
behavior. [DOM change](https://github.com/whatwg/dom/pull/1079) ·
[Firefox implementation](https://bugzilla.mozilla.org/show_bug.cgi?id=1773312).

## Decision

Apply the existing fallback name grammar in both parser paths. Use `E061`
for an unsupported name and preserve `E065` for malformed attribute syntax.
On an unsupported name, the adapter delegates to the fallback so the
diagnostic points to the attribute's starting column.

Apps using Alpine's `@click` shorthand inside an opted-in template can use
`x-on:click` or move the template outside the island. Revisit the grammar
when the browser support policy explicitly relies on relaxed name validation.
The [parser corpus spike](../template-parser-corpus-spike.md) records the
comparison and the three-browser probe.
