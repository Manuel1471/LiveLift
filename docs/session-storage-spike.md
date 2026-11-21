# Session storage across LiveView mounts

This spike is for LiveLift maintainers working on roadmap delivery 5.4
of the experimental release.

## Question

Can a stored browser value identify a single LiveView mount across
reloads and same-origin tabs?

## Method

Run `npm run e2e -- session_storage_spike.spec.mjs` from `bench/`.
Disconnect the native counter, make an unsent change, and write a test
value to `sessionStorage`. Reload and compare the stored value, visible
count, acknowledged sequence and mount identity. Separately open a
same-origin tab with an explicit opener and another without one. Check
whether they read the test value and whether the first tab can see a
deletion made in the opened tab.

## Acceptance

The tests must distinguish storage availability, mount identity and
ownership of the stored entry. Each case runs in Chromium, Firefox and
WebKit.

## Result

All six cases passed on 2026-11-21 against LiveView 1.2.13 in Chromium
158.0.8127.18, Firefox 159.0 and WebKit 27.2 on macOS arm64. The same six
cases also passed with `LIVE_LIFT_TEST_DEPLOY=1`. The stored
value survives a hard reload, but Phoenix mounts a new island with its
own state and acknowledgment sequence. An unsent increment in the old
island vanishes with the old DOM.

The tab with an explicit opener starts with a copy of the value. Removing
its copy leaves the original tab's value intact. A same-origin tab created
without an opener does not receive the entry.

## Limits and decision

The experiment establishes browser storage and mount lifecycles. It
does not test a persistence implementation, storage quota, malformed
entries or cross-account restoration.

Treat restored values as browser input. A stored entry alone cannot
prove which tab owns a pending mutation. A draft can be restored into an
explicitly opted-in form without executing an action. Replaying an
operation that changes server state across a reload would require an
identity and deduplication contract that survives both mount changes and
tab copies.

## Form restore follow-up

The same Playwright file also restores one saved text value directly
into the demo's existing `profile[note]` input after a reload. The
test writes the DOM value without dispatching an event, then observes
the LiveView WebSocket and the island's authoritative snapshot. A
different field triggers a render before the user submits the form.

In Chromium, Firefox and WebKit, restoring the text sent no event
and left the snapshot and acknowledgment unchanged. The next render
preserved the input, which has no server-bound `value` attribute.
The normal submit sent the restored text in `profile.note`. The test
held that event to distinguish the local prediction from Phoenix's
acknowledgment and verified convergence after delivery.

The expanded file passed nine cases in development and nine again
with `LIVE_LIFT_TEST_DEPLOY=1` on the same local matrix. The test
injects the restoration. It establishes the behavior of that form
while records, activation, expiry and other controls remain unverified.

## Storage failure follow-up

A sandboxed iframe with an opaque origin threw `SecurityError` on access
to `window.sessionStorage`, before any read. In a same-origin page, a
32 MiB test write to an existing key threw `QuotaExceededError` and left
the preceding value intact. This measures two browser behaviors.
The 32 MiB probe is neither a measured quota nor a LiveLift record limit.

These results apply to either restoration scope. Handle access to the
storage object as well as operations on it. Replace a previous record
with one write so a rejected replacement leaves the preceding copy
available.

The expanded spike passed all 15 cases in development and all 15 again
with `LIVE_LIFT_TEST_DEPLOY=1` on the same three-browser matrix. This
tests the browser storage primitive. Recovery from these failures in
the persistence feature remains to be verified.

## Server-bound input follow-up

The native list starts with a row whose label comes from Phoenix.
After a reload, the probe restores the label as an input property
without dispatching an event. Reversing the list preserves the draft.
Finding a new row then changes the existing row's title from `None`
to `New`, while the state and node identity of that row's label stay
the same. This render restores the input's canonical value and erases
the displayed draft. Replacing that row with a different key shows
the replacement's own label.

This case distinguishes moving a reused element from patching an
element with stable identity. Directly assigning the input property
is insufficient for a draft on a server-bound control. A persistence
implementation needs a policy for the displayed draft, the authoritative
value and the identity of the record through updates.

All 18 cases passed in development and all 18 again with digested
assets in Chromium, Firefox and WebKit.

[ADR-0005](decisions/ADR-0005-session-storage-scope.md) records the
restoration scopes and their acceptance checks.
