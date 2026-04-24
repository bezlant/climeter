# Ideas

## Codex Multi-Account Support

Climeter currently reads the active Codex CLI OAuth login and displays Codex usage separately from Claude usage. Future multi-account support should be designed explicitly instead of bolting onto the current active-login model.

Questions to resolve before implementation:

- Whether Codex CLI supports stable account selection without mutating global auth state.
- How to represent multiple Codex accounts without reading or logging sensitive auth payloads.
- Whether Codex account switching should be manual only, or whether any autoswitching behavior is desirable.
- How Codex switching would coexist with the existing Claude-only auto-switch behavior.

Preferred direction: keep Codex passive and account-scoped until the auth semantics are clear. If multi-account support is added, introduce an explicit provider/account abstraction first so Claude and Codex state remain separated and testable.
