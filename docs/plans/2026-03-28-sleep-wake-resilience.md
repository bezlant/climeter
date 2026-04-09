# Sleep/Wake Resilience + PopoverView Layout Fix

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Climeter survive macOS sleep/wake cycles without losing credentials or requiring app restarts, and fix the popover showing empty content.

**Architecture:** Add a `PowerStateMonitor` that observes `NSWorkspace` sleep/wake notifications and `DistributedNotificationCenter` screen lock/unlock notifications. On sleep, pause polling timers. On screen unlock, retry keychain reads and resume polling. Handle `errSecInDarkWake` (-25320) and `errAuthorizationInternal` (-60008) as transient errors instead of silent failures.

**Tech Stack:** AppKit (NSWorkspace), Foundation (DistributedNotificationCenter), Security framework

---

## Background

### Problem 1: Post-sleep keychain lockout

After macOS sleeps, the login keychain locks. The app's timers fire during dark wake (Power Nap), hit `errSecInDarkWake` (-25320) or `errAuthorizationInternal` (-60008), and silently lose all credentials. The app shows "0 authenticated" profiles until manually restarted.

Log evidence from 8 days of monitoring:
```
08:15:02 [keychain] read(...): OSStatus(-60008)   ← keychain locked after sleep
08:15:02 [profiles] init: 1 profiles, 0 authenticated  ← credentials lost
08:24:48 [cli-sync] readCLICredential: OSStatus(-25320) ← dark wake, no UI
12:10:30 [keychain] read(...): success(0)          ← user finally unlocked
```

### Problem 2: PopoverView empty content

The `ScrollView` in PopoverView has `.frame(maxHeight: 400)` without an intrinsic size hint. Inside `MenuBarExtra(.window)`, SwiftUI collapses it to 0px. Fix: add `.fixedSize(horizontal: false, vertical: true)`.

### Key API facts

- `NSWorkspace.didWakeNotification` fires on **full wake only**, not dark wake
- `com.apple.screenIsUnlocked` (DistributedNotificationCenter) fires when user authenticates at lock screen — this is when the keychain unlocks
- Both deliver on main thread when using `queue: .main`
- `NSWorkspace` notifications use `NSWorkspace.shared.notificationCenter`, NOT `NotificationCenter.default`

---

## Task 1: Add `PowerStateMonitor`

**Files:**
- Create: `Climeter/PowerStateMonitor.swift`
- Modify: `Climeter.xcodeproj/project.pbxproj` (add file reference)

**Step 1: Create PowerStateMonitor**

```swift
import AppKit
import Foundation

@MainActor
final class PowerStateMonitor: ObservableObject {
    @Published private(set) var isSystemAwake = true
    @Published private(set) var isScreenLocked = false

    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?
    var onScreenUnlocked: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    func startMonitoring() {
        let wsnc = NSWorkspace.shared.notificationCenter

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Log.profiles.info("system going to sleep — pausing coordinators")
            self?.isSystemAwake = false
            self?.onSleep?()
        })

        observers.append(wsnc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Log.profiles.info("system woke up — waiting for screen unlock")
            self?.isSystemAwake = true
            self?.onWake?()
        })

        let dnc = DistributedNotificationCenter.default()

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Log.profiles.info("screen locked")
            self?.isScreenLocked = true
        })

        observers.append(dnc.addObserver(
            forName: .init("com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Log.profiles.info("screen unlocked — retrying keychain + resuming polling")
            self?.isScreenLocked = false
            self?.onScreenUnlocked?()
        })
    }

    func stopMonitoring() {
        let wsnc = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()
        for observer in observers {
            wsnc.removeObserver(observer)
            dnc.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        stopMonitoring()
    }
}
```

**Step 2: Add to Xcode project**

Add PBXBuildFile, PBXFileReference, group child, and sources build phase entries for `PowerStateMonitor.swift` in `project.pbxproj` following the same pattern as `Log.swift` (IDs `1A000045...` and `1A000046...`).

**Step 3: Build and verify**

Run: `xcodebuild -scheme Climeter -configuration Debug build`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
feat: Add PowerStateMonitor for sleep/wake/lock detection
```

---

## Task 2: Wire PowerStateMonitor into ProfileManager

**Files:**
- Modify: `Climeter/ProfileManager.swift`
- Modify: `Climeter/ClimeterApp.swift`

**Step 1: Add sleep/wake handling to ProfileManager**

Add a `powerMonitor` property and wire the callbacks. On sleep: stop all coordinators. On screen unlock: re-read keychain, restart coordinators.

In `ProfileManager.swift`, add after `private var lastAutoSwitchDate: Date?` (line 16):

```swift
let powerMonitor = PowerStateMonitor()
```

Replace the current `init()` (lines 37-54) with:

```swift
init() {
    loadProfiles()
    refreshAuthenticatedIDs()
    loadCLIActiveProfileID()
    Log.profiles.info("init: \(self.profiles.count) profiles, \(self.authenticatedProfileIDs.count) authenticated, cliActive=\(self.cliActiveProfileID?.uuidString ?? "none")")
    setupAllCoordinators()

    // Read CLI keychain on background thread to avoid blocking the UI
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self else { return }
        Log.profiles.info("init: reading CLI keychain (background thread)...")
        let cliCredential = ClaudeCodeSyncService.readCLICredential()
        Log.profiles.info("init: CLI keychain read done, credential=\(cliCredential != nil)")
        DispatchQueue.main.async {
            self.handleCLICredential(cliCredential)
        }
    }

    setupPowerMonitor()
}
```

Add `setupPowerMonitor()` method in the Initialization section:

```swift
private func setupPowerMonitor() {
    powerMonitor.onSleep = { [weak self] in
        guard let self else { return }
        for coordinator in self.coordinators.values {
            coordinator.stopPolling()
        }
    }

    powerMonitor.onWake = { [weak self] in
        // Don't resume yet — keychain may still be locked.
        // Wait for onScreenUnlocked. But if screen lock is
        // not required (e.g. no password after sleep), wake
        // alone is enough — schedule a delayed retry.
        guard let self else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, !self.powerMonitor.isScreenLocked else { return }
            self.resumeAfterWake()
        }
    }

    powerMonitor.onScreenUnlocked = { [weak self] in
        self?.resumeAfterWake()
    }

    powerMonitor.startMonitoring()
}

private func resumeAfterWake() {
    Log.profiles.info("resumeAfterWake: re-reading keychain and restarting coordinators")
    refreshAuthenticatedIDs()
    Log.profiles.info("resumeAfterWake: \(self.authenticatedProfileIDs.count) authenticated")

    // Restart coordinators for any profiles that now have credentials
    for profile in profiles where authenticatedProfileIDs.contains(profile.id) {
        if coordinators[profile.id] == nil {
            setupCoordinator(for: profile.id)
        } else {
            coordinators[profile.id]?.startPolling()
        }
    }

    // Also re-read CLI keychain for any credential changes during sleep
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let cliCredential = ClaudeCodeSyncService.readCLICredential()
        DispatchQueue.main.async {
            self?.handleCLICredential(cliCredential)
        }
    }
}
```

**Step 2: Build and verify**

Run: `xcodebuild -scheme Climeter -configuration Debug build`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```
feat: Wire PowerStateMonitor to pause/resume coordinators on sleep/wake
```

---

## Task 3: Handle transient keychain errors gracefully

**Files:**
- Modify: `Climeter/KeychainService.swift`
- Modify: `Climeter/ClaudeCodeSyncService.swift`
- Modify: `Climeter/ProfileManager.swift`

**Step 1: Add `isTransientKeychainError` helper to Log.swift**

After the `keychainStatus` function in `Log.swift`:

```swift
static func isTransientKeychainError(_ status: OSStatus) -> Bool {
    status == errSecInteractionNotAllowed  // -25308
        || status == -25320               // errSecInDarkWake
        || status == -60008               // errAuthorizationInternal
}
```

**Step 2: Make `refreshAuthenticatedIDs` tolerant of transient errors**

Currently in `ProfileManager.swift` line 56-63, `refreshAuthenticatedIDs` calls `ProfileStore.loadCredentialModel` which uses `try?` — a transient keychain error wipes all credentials. Change to preserve existing cached credentials when keychain is locked.

Replace `refreshAuthenticatedIDs` (lines 56-63):

```swift
private func refreshAuthenticatedIDs() {
    var newCache: [UUID: Credential] = [:]
    for profile in profiles {
        if let credential = ProfileStore.loadCredentialModel(for: profile.id) {
            newCache[profile.id] = credential
        } else if let existing = cachedCredentials[profile.id] {
            // Keychain may be locked (sleep/dark wake) — keep cached credential
            Log.profiles.info("[\(profile.id)] keychain read failed, keeping cached credential")
            newCache[profile.id] = existing
        }
    }
    cachedCredentials = newCache
    authenticatedProfileIDs = Set(newCache.keys)
}
```

**Step 3: Build and verify**

Run: `xcodebuild -scheme Climeter -configuration Debug build`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```
fix: Preserve cached credentials when keychain is locked during sleep/wake
```

---

## Task 4: Fix PopoverView ScrollView layout

**Files:**
- Modify: `Climeter/PopoverView.swift:55-56`

**Step 1: Verify the fix is already in place**

The subagent already added `.fixedSize(horizontal: false, vertical: true)` on line 56. Verify it's there:

```swift
.frame(maxHeight: 400)
.fixedSize(horizontal: false, vertical: true)
```

**Step 2: Build, launch, and visually verify**

Run: `xcodebuild -scheme Climeter -configuration Debug build`
Launch: `open .../Debug/Climeter.app`
Verify: Click menu bar icon — Session and Week rows should be visible.

**Step 3: Commit**

```
fix: Fix PopoverView ScrollView collapsing to zero height in MenuBarExtra
```

---

## Task 5: Integration test — verify full sleep/wake cycle in logs

**Files:** None (manual verification)

**Step 1: Build release, deploy, and restart**

```bash
pkill -f "Climeter.app/Contents/MacOS/Climeter"
rm -rf /Applications/Climeter.app
xcodebuild -scheme Climeter -configuration Release build
cp -R .../Release/Climeter.app /Applications/Climeter.app
open /Applications/Climeter.app
```

**Step 2: Verify launch logs**

```bash
tail -20 ~/Library/Logs/Climeter/climeter.log
```

Expected: `init: 1 profiles, 1 authenticated` + successful fetch.

**Step 3: Simulate sleep/wake**

Lock the screen (Ctrl+Cmd+Q), wait 10 seconds, unlock. Check logs:

Expected log sequence:
```
[profiles] [INFO] screen locked
[profiles] [INFO] system going to sleep — pausing coordinators
[profiles] [INFO] system woke up — waiting for screen unlock
[profiles] [INFO] screen unlocked — retrying keychain + resuming polling
[profiles] [INFO] resumeAfterWake: re-reading keychain and restarting coordinators
[profiles] [INFO] resumeAfterWake: 1 authenticated
[coordinator] [INFO] poll cycle start (interval: 180.0s)
```

**Step 4: Verify no credential loss**

After unlock, the log should NOT show `0 authenticated`. The cached credentials should survive the sleep cycle.

---

## Edge Cases Considered

| Scenario | Expected Behavior |
|----------|-------------------|
| Dark wake (Power Nap) — timers fire | Timers stopped on willSleep, won't fire during dark wake |
| Wake without screen lock (no password required) | `onWake` fires, 3-second delayed retry succeeds since keychain is accessible |
| Wake with screen lock | `onWake` fires but `isScreenLocked=true` blocks the delayed retry. `onScreenUnlocked` handles it when user authenticates |
| Multiple rapid sleep/wake cycles | Each sleep stops timers, each wake restarts. `resumeAfterWake` is idempotent (re-reads keychain, starts polling only if not already running) |
| Keychain locked mid-poll | `refreshAuthenticatedIDs` preserves cached credentials instead of wiping them |
| App launched during dark wake (SMAppService) | Init reads keychain, gets `-25320`, but `setupPowerMonitor` ensures retry on screen unlock |
| CLI does `/login` while Mac is asleep | On wake+unlock, `resumeAfterWake` re-reads CLI keychain, picks up new credential |

---

## Version bump

After all tasks pass, bump `MARKETING_VERSION` to `1.0.5` in both Debug and Release configs, tag `v1.0.5`, push.
