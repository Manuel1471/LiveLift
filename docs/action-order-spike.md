# Optimistic action ordering spike

The original acknowledgement records the highest sequence applied to a
component. The client drops all pending predictions at or below that number.
This works while requests arrive in order, even when replies arrive out of
order.

We invoked the real marked dispatch wrapper with an increment action and an
initial count of zero. Sending sequence 2 before sequence 1 produced count 1
and acknowledgement 2 on both replies. The first action never ran because
its sequence was treated as a duplicate. The final count should be 2.

A cumulative acknowledgement must describe the contiguous prefix that the
server has applied. An action above the next expected sequence should return
the gap explicitly without running the handler. The client can then resend
the missing action from its pending queue. A genuine duplicate still receives
the current authoritative state and must not run the handler again.

Reconnect also needs an explicit decision about pending actions. Before the ordering change, the
hook dropped in-flight predictions and kept advancing its local sequence. A
contiguous protocol needs to resume from the server's acknowledged prefix and
retain enough information to retry actions that were sent without a reply.
Tests must cover a missing action, a retry after a lost reply, reordered
replies, and reconnection with unacknowledged actions.


The ordering implementation keeps the original sequence and event parameters
in the pending queue. A gap reply includes the server snapshot and
`expected_seq`. The hook retries the head of the queue and waits for progress
before sending the next action. Predictions remain visible during recovery.
The queue stays bounded to 100 actions. Unsequenced LiveView events preserve
the acknowledgement, so they cannot make a sequenced retry execute twice.

When a new snapshot resets the queue, the hook starts at the server's last
acknowledgement plus one. Retaining unacknowledged actions across disconnects
belongs to the reconnection delivery of phase 3.
