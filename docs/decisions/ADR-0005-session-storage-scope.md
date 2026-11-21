# ADR-0005 — Decide what persists across a local reload

Accepted for experimental LiveLift 5.4. For app and compiler maintainers.

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
browsers. The [server-bound input probe](../session-storage-spike.md#server-bound-input-follow-up)
found that a row can reuse the same input node while its next render
replaces a restored draft. The draft contract needs to account for
reconciliation and scope by record identity.

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

## Decision

Restore explicitly selected text fields. Use `data-live-lift-draft={@scope}`
on a named text input or textarea inside an identified `phx-submit` form.
The app supplies an opaque scope that distinguishes the current signed-in
session and record. Scope, route, island, form and field identify a draft.
Restore text as DOM input and keep it through patches for the same identity.
An explicit form reset clears the form's drafts. Submission uses the
existing LiveView action and validation. Forms can reject submissions, so
a submit attempt leaves the draft available until reset, scope change or
expiry.

Use one versioned record per field. Bound values to 4,096 UTF-16 code units
and expire them 30 minutes after the last input. Use the existing packaged
view extension so the shared runtime and the wire protocol stay unchanged.
The [storage failure follow-up](../session-storage-spike.md#storage-failure-follow-up)
motivates catching storage access and writes independently of form behavior.

## Verification

- The compiler emits the helper only for views with the attribute and rejects
  incompatible controls with a source location.
- Playwright verifies reload, Unicode and empty text, a bound input patch,
  ordinary native submit with a held acknowledgment, explicit reset and
  isolation across scope changes.
- Cover expired, malformed, oversized and wrong-scope records and simulate
  browser storage denial in the form demo. Run the three-browser matrix in
  development and with digested assets.
