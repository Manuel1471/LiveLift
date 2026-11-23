# Security model (experimental)

LiveLift runs selected app code in the browser. Treat browser state, event
parameters, and action sequences as untrusted, even when LiveLift generated
them. Keep authentication, authorization, persistence, and business rules in
the original LiveView handler.

## Trust boundaries

| Boundary | Current control | Remaining risk |
| --- | --- | --- |
| Server state to HTML | State is validated, JSON encoded, and escaped by HEEx. | Every island state field is visible in the page; never include secrets. |
| Template to DOM | The compiler rejects executable tags, `on*` attributes, and unsafe URL schemes, including entity-obfuscated prefixes. Dynamic values become text nodes or allowed attributes. | Templates are app-owned code. Do not compile untrusted template strings. |
| Browser event to server | Marked handlers receive normal LiveView events. The server validates bounded string params and nested maps and runs the original handler against its own assigns. Per-socket sequence numbers deduplicate marked events. | A client can forge values, event names, and sequence numbers. The app must validate domain rules and authorization. |
| Server reply to browser | Snapshots are validated and versioned; pending predictions replay after a newer reply. | In-flight events may have reached the server before a disconnect. Recovery retries unacknowledged events on the same instance, where sequences deduplicate them. New offline optimistic actions are queued in memory for up to 30 seconds. A page reload loses that queue. |

Optimistic actions send event parameters and a sequence through LiveView.
The server executes the handler against its own assigns. A mounted local
action sends zero events. When a user explicitly submits a value from local
UI, that value enters the regular LiveView handler as untrusted input.

## XSS and CSP review

App-owned template literals supply the static markup. Dynamic text is
written through text nodes or `textContent`. The generated actions use
ordinary JavaScript functions and are compatible with a CSP that disallows
`unsafe-eval`. Configure CSP and asset loading in the host application.

Static `href`, `xlink:href`, `src`, `action`, and `formaction` values may be relative or use
an allowed scheme. Both `href` forms also accept `mailto:` and `tel:`. Schemes hidden
with HTML character references, control characters, `javascript:`, and
`data:` are rejected at compilation. `base`, `link`, `meta`, `style`, SVG
animation tags, and `xml:base` are also rejected. Dynamic URL attributes are not in the
client template subset. Tests cover direct and encoded scheme attempts.

## Resource and prototype-pollution limits

State validation rejects unsafe map keys (`__proto__`, `constructor`, and
`prototype`), unsupported values, integers outside JavaScript's safe range,
more than 16 levels of nesting, lists over 10,000 elements, maps over 1,024
fields, trees over 50,000 nodes, and over 1 MiB of UTF-8 string content.
Optimistic events accept at most 64 string leaves in a map up to four segments deep and 64 KiB of combined
key/value content; the browser caps pending marked actions at 100. Both
Elixir and JavaScript enforce the state and event limits. These caps reduce
accidental or malicious resource use but do not replace LiveView's request
limits, rate limits, or application-level authorization.

This is an internal review of the current subset, not an external security
audit. A seeded corpus compiles 1,000 varied action expressions, checks that
unsupported forms raise an explicit compiler error, and syntax-checks every
generated action in Node. It does not cover arbitrary HEEx or all Elixir ASTs.
The [production limits](production-readiness.md) describe the verification completed for this release candidate.
