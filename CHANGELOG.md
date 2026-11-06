# Changelog

## Unreleased

- Keep server revision and server-owned values across island remounts and LiveView reconnects.
- Preserve focused controls while keyed rows move and isolate keys from sibling loops.
- Add real Chromium integration tests for client/server synchronization, editing and WCAG A/AA checks.
- Validate action rendering before committing the next client state.

## 0.1.0-rc.1 (prepared, not published)

- Initial experimental client templates, actions, keyed lists and app-defined components.
- Explicit LiveView event bridge with versioned server patches.
- Phoenix 1.8 installer, source maps, compatibility checks and benchmarks.
