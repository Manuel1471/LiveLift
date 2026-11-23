# ADR-0003 — Preserve native class commands on reused elements

Accepted for the class commands in experimental LiveLift 5.3. This record
is for compiler and runtime maintainers.

The [spike](../liveview-js-spike.md) shows that Phoenix can apply a class
to an island element and the next LiveLift render can erase it. Taking
the whole current class attribute would also erase changes from HEEx.
Reading Phoenix's private sticky state would couple the reconciler to an
internal representation.

Keep Phoenix as the executor. For templates containing a compiled class
command, generate a click listener that records only the command's
class additions and removals after the click reaches the window. The
tracker follows the frame boundaries of the supported immediate class
operations. Apply the recorded effects to each newly rendered class
attribute while reusing the target node. A replacement node starts with
its template classes.

The compiler admits literal commands and simple descendant selectors.
Transitions, delayed click bindings and selectors outside the source
element are beyond this increment. The browser comparison in
[js_commands_spike.spec.mjs](https://github.com/Manuel1471/LiveLift/blob/main/bench/e2e/js_commands_spike.spec.mjs)
checks the observed behavior against LiveView directly. Rerun that
comparison when upgrading the supported version of LiveView.
