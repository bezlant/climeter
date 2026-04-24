# Codex Usage Support Design

Date: 2026-04-24

## Goal

Add OpenAI Codex usage tracking to cliMeter with the same user-facing shape as Claude usage: a 5-hour session meter, a weekly meter, reset countdowns, stale/error states, and no manual token pasting.

The first implementation should track the currently logged-in Codex account. Multi-account Codex switching is intentionally out of scope for v1 because Codex stores the current login in a mutable `auth.json`, and public evidence shows session attribution is not reliable enough for multi-user dashboards without extra server/client support.

## Evidence

OpenAI documents Codex usage as plan-dependent and shaped around short-window usage plus a shared weekly limit. OpenAI also documents that local Codex usage is not available through Compliance API, so a public enterprise analytics API is not enough for local CLI usage.

Public Codex issues and CodexBar's implementation show two usable local-client sources:

- A direct ChatGPT/Codex backend usage endpoint using Codex OAuth credentials.
- Codex CLI RPC through `codex app-server` and `account/rateLimits/read`.

The direct backend path is fresher and less invasive than reading rollout JSONL session files. Session files are prompt-adjacent and should not be part of the v1 design.

## Recommendation

Use an API-first Codex provider:

1. Read Codex OAuth credentials from `~/.codex/auth.json` or `$CODEX_HOME/auth.json`.
2. Refresh stale access tokens with OpenAI's Codex OAuth refresh flow.
3. Fetch structured usage from `https://chatgpt.com/backend-api/wham/usage`.
4. Map returned rate-limit windows to cliMeter's existing session and weekly usage model.
5. Add CLI RPC as a future fallback only if the API path proves unreliable.

This is not an official public OpenAI API in the same sense as Anthropic's Claude usage endpoint. The implementation must be defensive, version-tolerant, and clear in its error states.

## Architecture

### CodexCredential

Value type containing:

- `accessToken`
- `refreshToken`
- `idToken`
- `accountID`
- `lastRefresh`
- `authMode`

`authMode` distinguishes ChatGPT OAuth credentials from API-key mode. If `auth.json` contains only `OPENAI_API_KEY`, cliMeter should report that Codex plan-limit usage is unavailable instead of trying to call the ChatGPT usage endpoint.

### CodexCredentialStore

Responsibilities:

- Resolve Codex home from `$CODEX_HOME` or `~/.codex`.
- Read only `auth.json`.
- Parse only the credential fields needed for usage.
- Save refreshed token fields while preserving unrelated keys in the auth file.
- Never log token values or raw auth JSON.

Failure states:

- Missing file: prompt user to run `codex login`.
- Malformed file: show a credential parse error.
- API-key mode: show a plan-limit-unavailable state.

### CodexTokenRefresher

Responsibilities:

- Refresh when `lastRefresh` is older than 8 days or when the API returns unauthorized.
- POST to `https://auth.openai.com/oauth/token`.
- Use Codex's OAuth client id.
- Persist refreshed tokens through `CodexCredentialStore`.

Refresh failure behavior:

- Expired, revoked, or reused refresh token: show "Codex session expired. Run `codex login`."
- Network failure: keep last usage snapshot if available and mark stale.
- Unknown response: show a concise refresh error and back off.

### CodexAPIService

Responsibilities:

- `GET https://chatgpt.com/backend-api/wham/usage`.
- Send `Authorization: Bearer <accessToken>`.
- Send `ChatGPT-Account-Id` when `accountID` is available.
- Decode only the fields used by cliMeter:
  - `plan_type`
  - `rate_limit.primary_window`
  - `rate_limit.secondary_window`
  - `credits`

The service must tolerate unknown plan types and additional fields.

### CodexUsageMapper

Responsibilities:

- Convert Codex rate-limit windows into `UsageData`.
- Classify windows by duration, not field name alone:
  - Around 18,000 seconds means the 5-hour session window.
  - Around 604,800 seconds means the weekly window.
- Fall back to primary/session and secondary/week only when durations are missing.
- Clamp usage percentages to 0...100.
- Convert epoch reset timestamps to `Date`.

If only one window is present, show partial usage with an explicit missing-window state rather than inventing data.

### Provider Integration

Claude usage remains unchanged. Codex is added as a second provider with its own coordinator and state.

The shared UI should consume provider-agnostic usage snapshots:

- Provider display name.
- Session usage window.
- Weekly usage window.
- Last successful refresh time.
- Error message.
- Stale state.

For v1, Codex does not participate in Claude auto-switch because Codex account switching is a separate problem with different auth semantics.

## UI

Popover:

- Keep existing Claude cards.
- Add a Codex card when Codex support is enabled or when credentials are detected.
- Show "Session" and "Week" rows using the same visual treatment as Claude.
- Show a Codex-specific empty state when no login is found.

Menu bar:

- Keep current Claude-driven icon behavior for the first implementation.
- Do not include Codex in the menu bar icon until provider selection or combined-provider icon behavior is designed separately.

Settings:

- Add a Codex toggle.
- Show the resolved credential source path.
- Show login state: connected, missing login, API-key mode, or expired session.
- No manual token fields in v1.

## Refresh Behavior

Use the existing 3-minute base polling interval. The direct usage endpoint is expected to be fresh, but it is not a formally documented public API and should not be polled more aggressively than Claude usage.

On failures:

- Preserve the last successful usage snapshot when possible.
- Mark data stale after 3 missed base refresh intervals.
- Use exponential backoff for repeated network, 429, or server failures.
- Manual refresh should remain available.

## Privacy And Security

The Codex provider must not read `~/.codex/sessions` or rollout JSONL files in v1.

The provider may read `~/.codex/auth.json` because the direct API path requires Codex OAuth credentials. Reads are limited to known credential fields.

Logs must not include:

- Access tokens.
- Refresh tokens.
- ID tokens.
- Raw auth JSON.
- Full response bodies.

Account identifiers and email should be redacted from diagnostic logs unless they are intentionally shown in UI.

## Testing Strategy

Add focused tests for behavior that can regress:

- Credential parsing for snake_case and camelCase token keys.
- API-key mode detection.
- Missing and malformed auth files.
- Token refresh response parsing and failure classification.
- Usage response decoding with known, missing, extra, and unknown fields.
- Window classification by duration, including reversed primary/secondary fields.
- Percentage clamping.
- Partial response handling.
- Stale-data behavior after refresh failures.

Avoid tests that require real OpenAI credentials or live network access. Use injected URL session or protocol-based HTTP clients for service tests.

## Out Of Scope

- Multi-account Codex profile switching.
- Reading Codex rollout JSONL/session files.
- Web dashboard scraping.
- Browser cookie import.
- Credits history or code-review remaining dashboards.
- Any behavior that sends model prompts to Codex or consumes Codex quota.

## Open Risks

- The `wham/usage` endpoint is not an official public API and may change.
- Codex auth file format may change.
- Token refresh semantics may change.
- Some workspaces may need account or organization routing not present in local credentials.

Mitigation is to keep the provider isolated, parse defensively, expose clear errors, and leave room for a CLI RPC fallback if direct API access becomes unreliable.
