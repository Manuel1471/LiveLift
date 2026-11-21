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
158.0.8127.18, Firefox 159.0 and WebKit 27.2 on macOS arm64. The stored
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
