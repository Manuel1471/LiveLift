# LiveView JS command spike

## Question

Which effects of native LiveView JavaScript commands survive a LiveLift
island update?

## Method

Run `npm run e2e -- js_commands_spike.spec.mjs` from `bench/`. The test
encodes `JS.toggle_class/2` and `JS.focus/1` using the installed LiveView
and attaches the resulting bindings to controls in the native counter.
It checks both outcomes before a marked label update and again afterward.
The run used LiveView 1.2.13 on macOS arm64 in Chromium, Firefox and WebKit.

## Result

All three browsers applied both commands through LiveView. After LiveLift
reconciled the label, the input focus was preserved and the class added
outside the template was removed. Native LiveView class persistence is
therefore a separate behavior to implement and verify in an island.

## Limits and decision

This tests an existing focused node and one patched class target. It
does not establish transition behavior, support for arbitrary selectors,
or persistence across remounts. Start with literal focus commands using
native event bindings. Keep class mutations outside that first allowlist
until a reconciliation contract is verified.
