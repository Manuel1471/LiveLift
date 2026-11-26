# Preformatted text parity spike

For LiveLift maintainers investigating the 0.1 release line.

## Question

Does the browser renderer preserve the same initial contents and control
values as Phoenix HEEx for leading line breaks in `pre` and `textarea`?

## Method

From the repository root, run:

```sh
mix compile
node bench/preformatted_text_spike.mjs
```

The fixture compiles nine HEEx templates through Phoenix and through both
LiveLift parser paths. It requires the same LiveLift tree from both parsers.
Playwright parses Phoenix's initial HTML and compares it with a render by
the real browser hook. The probe compares `pre.textContent` and both
`textarea.defaultValue` and `textarea.value` in the three bundled engines.

## Result

On 2026-11-25, against compiler and runtime sources at `b1cb47d`, Chromium
158.0.8127.18, Firefox 159.0, and WebKit 27.2 each differed in six cases.
The other three cases matched in all three engines.

| Case | Initial Phoenix HTML parsed by the browser | LiveLift render |
| --- | --- | --- |
| Literal leading LF or CRLF in either element | One leading line break removed | Leading LF retained |
| Binding starts with LF and contains CRLF in `pre` | Leading LF removed and interior CRLF normalized | Both retained |
| Same binding in `textarea` | Leading LF removed and interior CRLF normalized | Leading LF retained. `defaultValue` preserves interior CRLF, while `value` normalizes it |
| `pre` starts with an HTML comment before LF | LF retained | LF retained |
| Binding starts with text and contains LF in either element | Same text and values | Same text and values |

HTML parsing ignores the first LF token in `pre` and `textarea` and
normalizes source newlines. The client's DOM construction does not run the
markup through that parser. [HTML parsing standard](https://html.spec.whatwg.org/multipage/parsing.html#parsing-main-inbody).

## Decision

Use the Phoenix HTML result as the oracle for literal and bound text.
An unconditional trim on DOM text would break the leading-comment case.
Measure the eventual fix against the shared runtime limit, currently
8,192 gzip bytes. The probe covers initial contents and a full client
render. A fix also needs state transitions and a textarea with user edits
to verify reconciliation.
