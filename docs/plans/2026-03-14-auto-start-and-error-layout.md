# Auto-Start Sessions & Error Card Layout

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Auto-start the 5-hour usage window when session resets to 0% (CLI-active profile only), and make error states fill the full card width.

**Architecture:** Add a `startSession` method to `ClaudeAPIService` that sends a minimal Messages API call to `claude-haiku-4-5-20251001`. The coordinator detects 0% utilization and fires it once per reset cycle. Error card layout is a one-line SwiftUI frame change.

**Tech Stack:** Swift, SwiftUI, Anthropic Messages API (OAuth Bearer auth)

---

### Task 1: Add `startSession` to ClaudeAPIService

**Files:**
- Modify: `Climeter/ClaudeAPIService.swift`

**Step 1: Add the method**

Add after the `refreshToken` method (after line 74):

```swift
static func startSession(credential: Credential) async throws {
    let url = URL(string: "https://api.anthropic.com/v1/messages")!

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

    let body: [String: Any] = [
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 1,
        "messages": [["role": "user", "content": "hi"]]
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (_, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        return // Silent failure — not critical
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Climeter -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Climeter/ClaudeAPIService.swift
git commit -m "feat: add startSession API method for auto-starting 5-hour window"
```

---

### Task 2: Wire auto-start into UsageRefreshCoordinator

**Files:**
- Modify: `Climeter/UsageRefreshCoordinator.swift`

**Step 1: Add tracking state and callback**

Add property after `syncCLICredential` (after line 19):

```swift
private var lastAutoStartResetTime: Date?
private let onAutoStart: ((Credential) -> Void)?
```

Update `init` to accept `onAutoStart`:

```swift
init(profileID: UUID,
     credentialProvider: @escaping () -> Credential?,
     onCredentialRefreshed: ((Credential) -> Void)? = nil,
     syncCLICredential: (() -> Void)? = nil,
     onAutoStart: ((Credential) -> Void)? = nil) {
    self.profileID = profileID
    self.credentialProvider = credentialProvider
    self.onCredentialRefreshed = onCredentialRefreshed
    self.syncCLICredential = syncCLICredential
    self.onAutoStart = onAutoStart
}
```

**Step 2: Trigger auto-start after successful fetch**

In the `refresh()` method, after `self.usageData = fetchedData` and `self.errorMessage = nil` (the success path, around line 79), add:

```swift
self.checkAutoStart(credential: credential, usage: fetchedData)
```

Do this in BOTH success paths (the normal one ~line 79 and the 401-recovery one ~line 93).

**Step 3: Add the check method**

Add after `recoverCredential`:

```swift
private func checkAutoStart(credential: Credential, usage: UsageData) {
    guard onAutoStart != nil,
          usage.fiveHour.utilization == 0 else {
        lastAutoStartResetTime = nil
        return
    }
    // Only fire once per reset cycle
    let resetTime = usage.fiveHour.resetsAt
    guard lastAutoStartResetTime != resetTime else { return }
    lastAutoStartResetTime = resetTime
    onAutoStart?(credential)
}
```

**Step 4: Build and verify**

Run: `xcodebuild -scheme Climeter -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 5: Commit**

```bash
git add Climeter/UsageRefreshCoordinator.swift
git commit -m "feat: detect 0% usage and trigger auto-start callback"
```

---

### Task 3: Connect auto-start in ProfileManager

**Files:**
- Modify: `Climeter/ProfileManager.swift`

**Step 1: Add the `onAutoStart` callback in `setupCoordinator`**

In `setupCoordinator(for:)`, add the `onAutoStart` parameter to the `UsageRefreshCoordinator` init call, after the `syncCLICredential` closure:

```swift
onAutoStart: { [weak self] credential in
    guard self?.cliActiveProfileID == profileID else { return }
    Task {
        try? await ClaudeAPIService.startSession(credential: credential)
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Climeter -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Climeter/ProfileManager.swift
git commit -m "feat: wire auto-start for CLI-active profile on session reset"
```

---

### Task 4: Fix error card layout

**Files:**
- Modify: `Climeter/PopoverView.swift`

**Step 1: Make error state fill full card width**

In `ProfileCard`, find the error state block (the `else if let error = errorMessage` branch, ~line 188-196). Change from:

```swift
} else if let error = errorMessage {
    HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundColor(.orange)
        Text(error)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }
```

To:

```swift
} else if let error = errorMessage {
    HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundColor(.orange)
        Text(error)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity)
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Climeter -configuration Debug build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 3: Launch and visually verify**

Run: `open /path/to/DerivedData/Build/Products/Debug/Climeter.app`
Expected: Error messages stretch full card width, aligning with footer buttons.

**Step 4: Commit**

```bash
git add Climeter/PopoverView.swift
git commit -m "fix: make error state fill full card width"
```

---

### Task 5: Final build and smoke test

**Step 1: Clean build**

Run: `xcodebuild -scheme Climeter -configuration Debug clean build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

**Step 2: Launch and verify**

1. Open the app
2. Check popover displays normally (no regressions)
3. If possible, verify auto-start fires when session is at 0% (check next poll cycle after reset)
4. Verify error messages fill the full card width
