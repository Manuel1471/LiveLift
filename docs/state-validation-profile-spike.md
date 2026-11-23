# Row editing and state validation spike

Which work dominates an edit in a native LiveLift list, and which part
can be removed without changing the synchronization protocol?

The native-edit profile dispatches an input change in a list of 100 or
1,000 rows. It waits for the acknowledgment before changing the same row
again. Its local duration covers synchronous input handling and optimistic
rendering. The acknowledgment duration also includes Phoenix's server work
and applying the response. After ten warmups there are 100 timed edits,
followed by a separate set of 100 edits with Chromium's CPU sampler at
500 µs. The sampler stays outside the timed batch.

In the baseline 1,000-row run, sampled functions included Phoenix's
`createFragmentFromTemplate`, `indexTree` and `getNodeKey`, as well as
LiveLift's `validateValue`. The complete projected state was 34,867 bytes
in UTF-8 at 1,000 rows and 3,365 bytes at 100 rows. This counts the JSON
state in the DOM, excluding the WebSocket envelope, compression and any
additional rendered diff.

BEAM validation formats diagnostic paths inside the tight loop and
creates indexed tuples for each list. In the browser, regular expressions
have already restricted the accepted map keys and float tags to ASCII,
but byte accounting still creates an encoded array for each. These
costs can be removed while preserving the validation and error contract.

The next hypothesis is that a large list repeats avoidable work in
Phoenix's response rendering and DOM preparation. Determine its cost and
measure actual frame bytes before considering a smaller reply.
The spike does not establish how much a partial reply would save or what a
real phone would see. It keeps the current snapshots, timer semantics,
revision handling, and recovery behavior intact.

See the [validation report](progress/state-validation-optimization.md)
for the paired comparisons and reproductions.
