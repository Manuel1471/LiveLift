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
| Browser event to server | Marked handlers receive normal LiveView events. The server validates flat params and runs the original handler against its own assigns. Per-socket sequence numbers deduplicate marked events. | A client can forge values, event names, and sequence numbers. The app must validate domain rules and authorization. |
| Server reply to browser | Snapshots are validated and versioned; pending predictions replay after a newer reply. | In-flight events may have reached the server before a disconnect, so they are not resent. New offline actions are queued in memory for up to 30 seconds and replayed after the reconnect snapshot; a page reload loses them. |

The legacy `$server` bridge sends client-owned state as an event payload. Treat
it as a **proposed value**, validate it in the LiveView handler, and use server
assigns and authorization checks to decide whether to accept it. The native
`@client true` path sends event params, not client state, and executes the
original handler on server-owned assigns.

## XSS and CSP review

The runtime has two `innerHTML` assignments. Entity decoding uses a detached
element and a literal value from the compiled app template; the legacy
string-template mount likewise uses a generated app-owned literal. Neither
assignment receives state or event data. Dynamic text uses `textContent` or
text nodes. The runtime and generated actions use no `eval`, `new Function`,
or inline script generation. This design is compatible with a CSP that does
not allow `unsafe-eval`; the host app must still configure its own CSP and
asset loading policy.

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
Optimistic events accept at most 64 flat string params and 64 KiB of combined
key/value content; the browser caps pending marked actions at 100. Both
Elixir and JavaScript enforce the state and event limits. These caps reduce
accidental or malicious resource use but do not replace LiveView's request
limits, rate limits, or application-level authorization.

This is an internal review of the current subset, not an external security
audit. A seeded corpus compiles 1,000 varied action expressions, checks that
unsupported forms raise an explicit compiler error, and syntax-checks every
generated action in Node. It does not cover arbitrary HEEx or all Elixir ASTs.
The internal LiveView parser dependency, legacy event bridge, offline
behavior, many-island load, and browser compatibility remain release gates.
