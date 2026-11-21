# ADR-0005 — Decide what persists across a local reload

Proposed for experimental LiveLift 5.4. For app and compiler maintainers.

The [storage spike](../session-storage-spike.md) found that one stored
entry can coexist in two tabs while both tabs have independent LiveView
mounts. The current server acknowledgment belongs to one mount.
A storage key does not retain that acknowledgment across reloads.

## Option A — Restore explicitly selected draft fields

Keep attachment to existing LiveView forms. Store only fields the app
allows for a stable form within its session scope. Rehydrate the draft in
the browser. Let the person's next edit or submit follow the normal
LiveView path. This preserves typed input across a reload. It also means
that restored text has the same authority as input typed in the browser.
The [form restore follow-up](../session-storage-spike.md#form-restore-follow-up)
verified the normal submit path with an existing nested input in three
browsers.

Acceptance requires preserving an eligible draft across reload, keeping
Phoenix state and action sequences untouched before user interaction, and
verifying that the ordinary submit sees the restored input. Tests must cover
wrong scopes, expiration, malformed or oversized data, and denied
browser storage.

## Option B — Restore pending operations

Give a pending operation an identity that survives a LiveView mount.
Use application and session scope to decide where it can run. Acknowledge
successful application authoritatively so that copies of the operation in
two tabs cannot both take effect. This also needs an expiry and a replay
policy for pending operations that may already have reached Phoenix.

Acceptance would include duplicated tab copies and independent reloads,
an interrupted delivery with uncertain acknowledgment, expiry, and real
server convergence. This path requires agreement on the protocol and
deduplication lifetime.

## Open decision

Choose the initial restoration scope before introducing a public opt-in.
The draft option fits the existing server-authoritative protocol. Both
options require versioned records, validation, bounded storage and
an explicit opt-in. The [storage failure follow-up](../session-storage-spike.md#storage-failure-follow-up)
shows that obtaining storage may throw and that a rejected replacement
can retain the previous value.
