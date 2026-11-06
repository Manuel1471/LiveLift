# Changelog

## Unreleased

- Replace dynamic text wrapper spans with text nodes bounded by comments, preserving native markup.
- Cover 1,000 generated action states and 1,000 template renders with seeded Elixir/JavaScript parity checks.
- Match HTML attribute entities and native checkbox, select and textarea values across server and browser rendering.
- Document LiveView-shaped API feasibility spikes and formal client semantics.
- Exclude the release guide from Hex and run CI on Elixir 1.18/OTP 27 and Elixir 1.20/OTP 29.
- Keep server revision and server-owned values across island remounts and LiveView reconnects.
- Preserve focused controls while keyed rows move and isolate keys from sibling loops.
- Add real Chromium integration tests for client/server synchronization, editing and WCAG A/AA checks.
- Validate action rendering before committing the next client state.

## 0.1.0-rc.1 (prepared, not published)

- Initial experimental client templates, actions, keyed lists and app-defined components.
- Explicit LiveView event bridge with versioned server patches.
- Phoenix 1.8 installer, source maps, compatibility checks and benchmarks.
