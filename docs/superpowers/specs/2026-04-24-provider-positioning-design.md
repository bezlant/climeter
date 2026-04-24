# Provider Positioning Design

## Goal

Update cliMeter's user-facing copy and static landing page so the product is presented as a focused OpenAI Codex and Anthropic Claude usage monitor, without implying generic AI provider support.

## Scope

- Keep Claude usage behavior, multi-account support, auto-switch, and menu bar icon behavior unchanged.
- Keep Codex usage separate from Claude auto-switch.
- Add Claude/Anthropic setup context in Settings similar to the Codex/OpenAI note.
- Update README and landing page copy to describe both supported providers.
- Fix the popover empty state so Codex can still appear when no Claude account is connected.

## User-Facing Model

Claude and Codex are separate providers:

- Claude Code usage is backed by Anthropic credentials stored by Claude Code in macOS Keychain.
- Codex usage is backed by OpenAI Codex CLI credentials from `$CODEX_HOME/auth.json` or `~/.codex/auth.json`.
- Claude auto-switch applies only to Claude profiles.
- Codex displays its own status and errors, but does not participate in account switching.

## Landing Page

The landing page should lead with "OpenAI Codex and Anthropic Claude" rather than "Claude Code only." It should still be precise:

- Mention Claude Code and Codex by name.
- Avoid broad "AI usage monitor" claims.
- Show both providers in the mock popover.
- Keep privacy claims provider-aware: Anthropic endpoints for Claude usage, OpenAI/ChatGPT endpoints for Codex usage.

## Verification

- Build and test the macOS app after SwiftUI copy/empty-state changes.
- Open `dist/index.html` locally and visually inspect desktop/mobile layout.
- Confirm no real auth files are read or committed.
