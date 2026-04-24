# Codex Usage Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add API-first OpenAI Codex session and weekly usage tracking to cliMeter without reading Codex session/rollout files.

**Architecture:** Add a Codex provider beside the existing Claude provider. The provider reads only Codex OAuth credentials from `auth.json`, refreshes tokens after the 8-day refresh threshold or an unauthorized usage response, calls the ChatGPT/Codex usage endpoint, maps rate-limit windows into the existing `UsageData` shape, and renders a separate Codex card in the popover.

**Tech Stack:** Swift 5, SwiftUI, Foundation URLSession, XCTest, Xcode macOS app target.

---

## File Structure

- Create `Climeter/CodexCredential.swift`: Codex auth value types, auth mode detection, `auth.json` parsing, and safe save preparation.
- Create `Climeter/CodexCredentialStore.swift`: resolves `$CODEX_HOME` or `~/.codex`, reads/writes only `auth.json`.
- Create `Climeter/CodexAPIService.swift`: Codex usage endpoint decoding and token refresh HTTP calls.
- Create `Climeter/CodexUsageMapper.swift`: maps Codex response windows into `UsageData`.
- Create `Climeter/CodexUsageRefreshCoordinator.swift`: Codex polling, refresh, backoff, stale preservation, and user-facing error messages.
- Modify `Climeter/ProfileManager.swift`: owns Codex coordinator state and exposes Codex usage/error/loading fields.
- Modify `Climeter/PopoverView.swift`: shows a Codex card below existing Claude profile cards.
- Modify `Climeter/SettingsView.swift`: adds a Codex section with enable/status/path display.
- Modify `Climeter/ProfileStore.swift`: persists Codex provider enabled state.
- Modify `Climeter.xcodeproj/project.pbxproj`: adds new app source files and a `ClimeterTests` unit test target.
- Create `ClimeterTests/CodexCredentialTests.swift`.
- Create `ClimeterTests/CodexUsageMapperTests.swift`.
- Create `ClimeterTests/CodexAPIServiceTests.swift`.
- Create `ClimeterTests/CodexUsageRefreshCoordinatorTests.swift`.

## Verification Commands

Use these commands throughout:

```bash
xcodebuild -scheme Climeter -configuration Debug build
xcodebuild -scheme Climeter -configuration Debug test
```

Known environment note: `xcodebuild -list` currently emits a CoreSimulator warning on this Mac, but the project is macOS-only and still lists the `Climeter` scheme. Treat simulator warnings as non-blocking unless the macOS build or test action fails.

---

### Task 1: Add Unit Test Target

**Files:**
- Modify: `Climeter.xcodeproj/project.pbxproj`
- Modify: `Climeter.xcodeproj/xcshareddata/xcschemes/Climeter.xcscheme`
- Create: `ClimeterTests/ClimeterTests.swift`

- [ ] **Step 1: Add a minimal failing test file**

Create `ClimeterTests/ClimeterTests.swift`:

```swift
import XCTest
@testable import Climeter

final class ClimeterTests: XCTestCase {
    func test_testTargetIsWired() {
        XCTAssertEqual(UsageWindow(utilization: 12, resetsAt: nil).utilization, 12)
    }
}
```

- [ ] **Step 2: Add `ClimeterTests` to the Xcode project**

In `Climeter.xcodeproj/project.pbxproj`, add a macOS unit test target named `ClimeterTests` with:

```text
productType = "com.apple.product-type.bundle.unit-test";
PRODUCT_BUNDLE_IDENTIFIER = com.bezlant.climeter.tests;
TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Climeter.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Climeter";
BUNDLE_LOADER = "$(TEST_HOST)";
GENERATE_INFOPLIST_FILE = YES;
SWIFT_VERSION = 5.0;
MACOSX_DEPLOYMENT_TARGET = 14.0;
```

Add `ClimeterTests.swift` to the test target sources and add the test target as a dependency of the test action in `Climeter.xcodeproj/xcshareddata/xcschemes/Climeter.xcscheme`.

- [ ] **Step 3: Run tests to verify the target is wired**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: `TEST SUCCEEDED` and `test_testTargetIsWired` passes.

- [ ] **Step 4: Commit**

```bash
git add Climeter.xcodeproj/project.pbxproj Climeter.xcodeproj/xcshareddata/xcschemes/Climeter.xcscheme ClimeterTests/ClimeterTests.swift
git commit -m "test: add climeter unit test target"
```

---

### Task 2: Parse Codex Credentials Safely

**Files:**
- Create: `Climeter/CodexCredential.swift`
- Create: `Climeter/CodexCredentialStore.swift`
- Create: `ClimeterTests/CodexCredentialTests.swift`
- Modify: `Climeter.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing credential tests**

Create `ClimeterTests/CodexCredentialTests.swift`:

```swift
import XCTest
@testable import Climeter

final class CodexCredentialTests: XCTestCase {
    func test_parseOAuthSnakeCaseAuthJSON() throws {
        let data = Data("""
        {
          "tokens": {
            "access_token": "access-1",
            "refresh_token": "refresh-1",
            "id_token": "id-1",
            "account_id": "account-1"
          },
          "last_refresh": "2026-04-23T12:00:00Z"
        }
        """.utf8)

        let credential = try CodexCredential.parse(data: data)

        XCTAssertEqual(credential.authMode, .chatGPT)
        XCTAssertEqual(credential.accessToken, "access-1")
        XCTAssertEqual(credential.refreshToken, "refresh-1")
        XCTAssertEqual(credential.idToken, "id-1")
        XCTAssertEqual(credential.accountID, "account-1")
        XCTAssertFalse(credential.needsRefresh(now: ISO8601DateFormatter().date(from: "2026-04-24T12:00:00Z")!))
    }

    func test_parseOAuthCamelCaseAuthJSON() throws {
        let data = Data("""
        {
          "tokens": {
            "accessToken": "access-2",
            "refreshToken": "refresh-2",
            "idToken": "id-2",
            "accountId": "account-2"
          },
          "last_refresh": "2026-04-01T12:00:00Z"
        }
        """.utf8)

        let credential = try CodexCredential.parse(data: data)

        XCTAssertEqual(credential.authMode, .chatGPT)
        XCTAssertEqual(credential.accessToken, "access-2")
        XCTAssertEqual(credential.refreshToken, "refresh-2")
        XCTAssertEqual(credential.idToken, "id-2")
        XCTAssertEqual(credential.accountID, "account-2")
        XCTAssertTrue(credential.needsRefresh(now: ISO8601DateFormatter().date(from: "2026-04-24T12:00:00Z")!))
    }

    func test_parseAPIKeyMode() throws {
        let data = Data(#"{ "OPENAI_API_KEY": "sk-test" }"#.utf8)

        let credential = try CodexCredential.parse(data: data)

        XCTAssertEqual(credential.authMode, .apiKey)
        XCTAssertEqual(credential.accessToken, "sk-test")
        XCTAssertEqual(credential.refreshToken, "")
    }

    func test_missingTokensThrows() {
        let data = Data(#"{ "tokens": {} }"#.utf8)

        XCTAssertThrowsError(try CodexCredential.parse(data: data)) { error in
            XCTAssertEqual(error as? CodexCredentialError, .missingTokens)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: FAIL because `CodexCredential` and `CodexCredentialError` do not exist.

- [ ] **Step 3: Implement credential parsing**

Create `Climeter/CodexCredential.swift`:

```swift
import Foundation

enum CodexAuthMode: Equatable {
    case chatGPT
    case apiKey
}

enum CodexCredentialError: Error, Equatable {
    case invalidJSON
    case missingTokens
}

struct CodexCredential: Equatable {
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var accountID: String?
    var lastRefresh: Date?
    var authMode: CodexAuthMode

    func needsRefresh(now: Date = Date()) -> Bool {
        guard authMode == .chatGPT else { return false }
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) > 8 * 24 * 60 * 60
    }

    static func parse(data: Data) throws -> CodexCredential {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexCredentialError.invalidJSON
        }

        if let apiKey = json["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CodexCredential(
                accessToken: apiKey,
                refreshToken: "",
                idToken: nil,
                accountID: nil,
                lastRefresh: nil,
                authMode: .apiKey
            )
        }

        guard let tokens = json["tokens"] as? [String: Any] else {
            throw CodexCredentialError.missingTokens
        }
        guard let accessToken = string(in: tokens, snake: "access_token", camel: "accessToken"),
              let refreshToken = string(in: tokens, snake: "refresh_token", camel: "refreshToken"),
              !accessToken.isEmpty else {
            throw CodexCredentialError.missingTokens
        }

        return CodexCredential(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: string(in: tokens, snake: "id_token", camel: "idToken"),
            accountID: string(in: tokens, snake: "account_id", camel: "accountId"),
            lastRefresh: parseDate(json["last_refresh"]),
            authMode: .chatGPT
        )
    }

    private static func string(in dictionary: [String: Any], snake: String, camel: String) -> String? {
        if let value = dictionary[snake] as? String, !value.isEmpty { return value }
        if let value = dictionary[camel] as? String, !value.isEmpty { return value }
        return nil
    }

    private static func parseDate(_ raw: Any?) -> Date? {
        guard let value = raw as? String, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
```

Create `Climeter/CodexCredentialStore.swift`:

```swift
import Foundation

enum CodexCredentialStoreError: Error, Equatable {
    case notFound(String)
}

enum CodexCredentialStore {
    static func codexHome(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = env["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static func authFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        codexHome(env: env).appendingPathComponent("auth.json")
    }

    static func load(env: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexCredential {
        let url = authFileURL(env: env)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexCredentialStoreError.notFound(url.path)
        }
        return try CodexCredential.parse(data: Data(contentsOf: url))
    }
}
```

- [ ] **Step 4: Add files to app and test targets**

Modify `Climeter.xcodeproj/project.pbxproj` so:

- `CodexCredential.swift` and `CodexCredentialStore.swift` are in the `Climeter` group and app target sources.
- `CodexCredentialTests.swift` is in the `ClimeterTests` group and test target sources.

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: PASS for all `CodexCredentialTests`.

- [ ] **Step 6: Commit**

```bash
git add Climeter/CodexCredential.swift Climeter/CodexCredentialStore.swift ClimeterTests/CodexCredentialTests.swift Climeter.xcodeproj/project.pbxproj
git commit -m "feat: parse codex credentials"
```

---

### Task 3: Decode And Map Codex Usage

**Files:**
- Create: `Climeter/CodexAPIService.swift`
- Create: `Climeter/CodexUsageMapper.swift`
- Create: `ClimeterTests/CodexUsageMapperTests.swift`
- Modify: `Climeter.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing usage mapper tests**

Create `ClimeterTests/CodexUsageMapperTests.swift`:

```swift
import XCTest
@testable import Climeter

final class CodexUsageMapperTests: XCTestCase {
    func test_mapsPrimaryAndSecondaryByWindowDuration() throws {
        let response = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimitDetails(
                primaryWindow: CodexWindowSnapshot(usedPercent: 25, resetAt: 1_777_100_000, limitWindowSeconds: 18_000),
                secondaryWindow: CodexWindowSnapshot(usedPercent: 40, resetAt: 1_777_600_000, limitWindowSeconds: 604_800)
            ),
            credits: nil
        )

        let usage = try CodexUsageMapper.map(response)

        XCTAssertEqual(usage.fiveHour.utilization, 25)
        XCTAssertEqual(usage.sevenDay.utilization, 40)
        XCTAssertEqual(usage.fiveHour.resetsAt, Date(timeIntervalSince1970: 1_777_100_000))
        XCTAssertEqual(usage.sevenDay.resetsAt, Date(timeIntervalSince1970: 1_777_600_000))
    }

    func test_mapsReversedWindowsByDuration() throws {
        let response = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimitDetails(
                primaryWindow: CodexWindowSnapshot(usedPercent: 70, resetAt: 1_777_600_000, limitWindowSeconds: 604_800),
                secondaryWindow: CodexWindowSnapshot(usedPercent: 15, resetAt: 1_777_100_000, limitWindowSeconds: 18_000)
            ),
            credits: nil
        )

        let usage = try CodexUsageMapper.map(response)

        XCTAssertEqual(usage.fiveHour.utilization, 15)
        XCTAssertEqual(usage.sevenDay.utilization, 70)
    }

    func test_clampsPercentages() throws {
        let response = CodexUsageResponse(
            planType: "pro",
            rateLimit: CodexRateLimitDetails(
                primaryWindow: CodexWindowSnapshot(usedPercent: -5, resetAt: 1_777_100_000, limitWindowSeconds: 18_000),
                secondaryWindow: CodexWindowSnapshot(usedPercent: 140, resetAt: 1_777_600_000, limitWindowSeconds: 604_800)
            ),
            credits: nil
        )

        let usage = try CodexUsageMapper.map(response)

        XCTAssertEqual(usage.fiveHour.utilization, 0)
        XCTAssertEqual(usage.sevenDay.utilization, 100)
    }

    func test_missingWindowsThrowsNoUsage() {
        let response = CodexUsageResponse(planType: "pro", rateLimit: nil, credits: nil)

        XCTAssertThrowsError(try CodexUsageMapper.map(response)) { error in
            XCTAssertEqual(error as? CodexUsageMapperError, .missingWindows)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: FAIL because Codex usage response and mapper types do not exist.

- [ ] **Step 3: Implement response models and mapper**

Create the model declarations at the top of `Climeter/CodexAPIService.swift`:

```swift
import Foundation

struct CodexUsageResponse: Decodable, Equatable {
    let planType: String?
    let rateLimit: CodexRateLimitDetails?
    let credits: CodexCreditDetails?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }
}

struct CodexRateLimitDetails: Decodable, Equatable {
    let primaryWindow: CodexWindowSnapshot?
    let secondaryWindow: CodexWindowSnapshot?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

struct CodexWindowSnapshot: Decodable, Equatable {
    let usedPercent: Int
    let resetAt: Int
    let limitWindowSeconds: Int

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }
}

struct CodexCreditDetails: Decodable, Equatable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: Double?

    enum CodingKeys: String, CodingKey {
        case hasCredits = "has_credits"
        case unlimited
        case balance
    }
}
```

Create `Climeter/CodexUsageMapper.swift`:

```swift
import Foundation

enum CodexUsageMapperError: Error, Equatable {
    case missingWindows
}

enum CodexUsageMapper {
    static func map(_ response: CodexUsageResponse) throws -> UsageData {
        guard let rateLimit = response.rateLimit else {
            throw CodexUsageMapperError.missingWindows
        }

        let windows = [rateLimit.primaryWindow, rateLimit.secondaryWindow].compactMap(\.self)
        guard !windows.isEmpty else {
            throw CodexUsageMapperError.missingWindows
        }

        let session = window(near: 18_000, in: windows) ?? rateLimit.primaryWindow
        let weekly = window(near: 604_800, in: windows) ?? rateLimit.secondaryWindow

        guard let session, let weekly else {
            throw CodexUsageMapperError.missingWindows
        }

        return UsageData(
            fiveHour: usageWindow(from: session),
            sevenDay: usageWindow(from: weekly)
        )
    }

    private static func window(near target: Int, in windows: [CodexWindowSnapshot]) -> CodexWindowSnapshot? {
        windows.min { lhs, rhs in
            abs(lhs.limitWindowSeconds - target) < abs(rhs.limitWindowSeconds - target)
        }.flatMap { candidate in
            abs(candidate.limitWindowSeconds - target) <= target / 10 ? candidate : nil
        }
    }

    private static func usageWindow(from snapshot: CodexWindowSnapshot) -> UsageWindow {
        UsageWindow(
            utilization: min(100, max(0, Double(snapshot.usedPercent))),
            resetsAt: Date(timeIntervalSince1970: TimeInterval(snapshot.resetAt))
        )
    }
}
```

- [ ] **Step 4: Add files to project**

Modify `Climeter.xcodeproj/project.pbxproj` so:

- `CodexAPIService.swift` and `CodexUsageMapper.swift` are in the app target sources.
- `CodexUsageMapperTests.swift` is in the test target sources.

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: PASS for `CodexUsageMapperTests`.

- [ ] **Step 6: Commit**

```bash
git add Climeter/CodexAPIService.swift Climeter/CodexUsageMapper.swift ClimeterTests/CodexUsageMapperTests.swift Climeter.xcodeproj/project.pbxproj
git commit -m "feat: map codex usage windows"
```

---

### Task 4: Fetch Codex Usage And Refresh Tokens

**Files:**
- Modify: `Climeter/CodexAPIService.swift`
- Modify: `Climeter/CodexCredential.swift`
- Create: `ClimeterTests/CodexAPIServiceTests.swift`
- Modify: `Climeter.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing API construction tests**

Create `ClimeterTests/CodexAPIServiceTests.swift`:

```swift
import XCTest
@testable import Climeter

final class CodexAPIServiceTests: XCTestCase {
    func test_usageRequestContainsBearerAndAccountHeaders() throws {
        let request = CodexAPIService.makeUsageRequest(
            accessToken: "access-token",
            accountID: "account-id"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-id")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func test_usageRequestOmitsEmptyAccountHeader() throws {
        let request = CodexAPIService.makeUsageRequest(accessToken: "access-token", accountID: nil)

        XCTAssertNil(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
    }

    func test_decodeUsageResponse() throws {
        let data = Data("""
        {
          "plan_type": "pro",
          "rate_limit": {
            "primary_window": { "used_percent": 11, "reset_at": 1777100000, "limit_window_seconds": 18000 },
            "secondary_window": { "used_percent": 22, "reset_at": 1777600000, "limit_window_seconds": 604800 }
          },
          "credits": { "has_credits": true, "unlimited": false, "balance": 12.5 }
        }
        """.utf8)

        let decoded = try CodexAPIService.decodeUsageResponse(data)

        XCTAssertEqual(decoded.planType, "pro")
        XCTAssertEqual(decoded.rateLimit?.primaryWindow?.usedPercent, 11)
        XCTAssertEqual(decoded.credits?.balance, 12.5)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: FAIL because `CodexAPIService.makeUsageRequest` and `decodeUsageResponse` do not exist.

- [ ] **Step 3: Implement request construction and decoding**

Append to `Climeter/CodexAPIService.swift`:

```swift
enum CodexAPIError: Error, Equatable {
    case invalidResponse
    case httpError(Int)
    case unauthorized
    case decodingError
}

enum CodexAPIService {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static func makeUsageRequest(accessToken: String, accountID: String?) -> URLRequest {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Climeter", forHTTPHeaderField: "User-Agent")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    static func decodeUsageResponse(_ data: Data) throws -> CodexUsageResponse {
        do {
            return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            throw CodexAPIError.decodingError
        }
    }

    static func fetchUsage(credential: CodexCredential) async throws -> UsageData {
        let request = makeUsageRequest(accessToken: credential.accessToken, accountID: credential.accountID)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexAPIError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return try CodexUsageMapper.map(decodeUsageResponse(data))
        case 401, 403:
            throw CodexAPIError.unauthorized
        default:
            throw CodexAPIError.httpError(http.statusCode)
        }
    }
}
```

- [ ] **Step 4: Add token refresh request helpers**

Add tests to `ClimeterTests/CodexAPIServiceTests.swift`:

```swift
func test_refreshRequestBody() throws {
    let request = try CodexTokenRefresher.makeRefreshRequest(refreshToken: "refresh-token")

    XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/oauth/token")
    XCTAssertEqual(request.httpMethod, "POST")
    XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
    XCTAssertEqual(json["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
    XCTAssertEqual(json["grant_type"], "refresh_token")
    XCTAssertEqual(json["refresh_token"], "refresh-token")
    XCTAssertEqual(json["scope"], "openid profile email")
}
```

Create the implementation in `Climeter/CodexAPIService.swift`:

```swift
enum CodexTokenRefresher {
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    static func makeRefreshRequest(refreshToken: String) throws -> URLRequest {
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email"
        ])
        return request
    }
}
```

- [ ] **Step 5: Add test file to project and run tests**

Modify `Climeter.xcodeproj/project.pbxproj` so `CodexAPIServiceTests.swift` is in the test target sources.

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: PASS for `CodexAPIServiceTests`.

- [ ] **Step 6: Commit**

```bash
git add Climeter/CodexAPIService.swift ClimeterTests/CodexAPIServiceTests.swift Climeter.xcodeproj/project.pbxproj
git commit -m "feat: add codex usage api client"
```

---

### Task 5: Add Codex Refresh Coordinator

**Files:**
- Create: `Climeter/CodexUsageRefreshCoordinator.swift`
- Create: `ClimeterTests/CodexUsageRefreshCoordinatorTests.swift`
- Modify: `Climeter.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing coordinator error tests**

Create `ClimeterTests/CodexUsageRefreshCoordinatorTests.swift`:

```swift
import XCTest
@testable import Climeter

final class CodexUsageRefreshCoordinatorTests: XCTestCase {
    func test_describeErrorForMissingLogin() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexCredentialStoreError.notFound("/tmp/auth.json")),
            "Run `codex login`"
        )
    }

    func test_describeErrorForAPIKeyMode() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexUsageRefreshError.apiKeyMode),
            "Codex API key mode: plan limits unavailable"
        )
    }

    func test_describeErrorForUnauthorized() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.describeError(CodexAPIError.unauthorized),
            "Codex session expired. Run `codex login`"
        )
    }

    func test_staleThresholdIsThreeBaseIntervals() {
        XCTAssertEqual(
            CodexUsageRefreshCoordinator.staleThreshold,
            CodexUsageRefreshCoordinator.baseInterval * 3
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: FAIL because `CodexUsageRefreshCoordinator` does not exist.

- [ ] **Step 3: Implement coordinator skeleton**

Create `Climeter/CodexUsageRefreshCoordinator.swift`:

```swift
import Foundation
import SwiftUI

enum CodexUsageRefreshError: Error, Equatable {
    case apiKeyMode
}

@MainActor
final class CodexUsageRefreshCoordinator: ObservableObject {
    @Published var usageData: UsageData?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastSuccessAt: Date?

    static let baseInterval: TimeInterval = 180
    static let staleThreshold: TimeInterval = baseInterval * 3

    private var timer: Timer?
    private var currentInterval: TimeInterval = baseInterval
    private let maxInterval: TimeInterval = 900

    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleNextPoll()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task { @MainActor in
            defer { self.isLoading = false }
            do {
                var credential = try CodexCredentialStore.load()
                guard credential.authMode == .chatGPT else {
                    throw CodexUsageRefreshError.apiKeyMode
                }
                if credential.needsRefresh() {
                    credential = try await CodexTokenRefresher.refresh(credential)
                    try CodexCredentialStore.save(credential)
                }
                let usage = try await CodexAPIService.fetchUsage(credential: credential)
                self.usageData = usage
                self.errorMessage = nil
                self.lastSuccessAt = Date()
                self.stepDownBackoff()
            } catch {
                self.handleError(error)
            }
        }
    }

    private func scheduleNextPoll() {
        timer?.invalidate()
        let jitter = Double.random(in: 0.9...1.1)
        timer = Timer.scheduledTimer(withTimeInterval: currentInterval * jitter, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
                self?.scheduleNextPoll()
            }
        }
    }

    private func handleError(_ error: Error) {
        if case CodexAPIError.httpError(429) = error {
            currentInterval = min(currentInterval * 2, maxInterval)
            scheduleNextPoll()
        }
        if usageData == nil {
            errorMessage = Self.describeError(error)
        }
    }

    private func stepDownBackoff() {
        guard currentInterval > Self.baseInterval else { return }
        currentInterval = max(currentInterval / 2, Self.baseInterval)
        scheduleNextPoll()
    }

    static func describeError(_ error: Error) -> String {
        if case CodexCredentialStoreError.notFound = error {
            return "Run `codex login`"
        }
        if case CodexUsageRefreshError.apiKeyMode = error {
            return "Codex API key mode: plan limits unavailable"
        }
        if case CodexAPIError.unauthorized = error {
            return "Codex session expired. Run `codex login`"
        }
        if case CodexAPIError.httpError(429) = error {
            return "Rate limited - retrying soon"
        }
        if case CodexUsageMapperError.missingWindows = error {
            return "Codex usage format changed"
        }
        return "Codex usage unavailable"
    }

    deinit {
        timer?.invalidate()
    }
}
```

- [ ] **Step 4: Add missing save and refresh functions**

Add to `Climeter/CodexCredentialStore.swift`:

```swift
static func save(_ credential: CodexCredential, env: [String: String] = ProcessInfo.processInfo.environment) throws {
    let url = authFileURL(env: env)
    var json: [String: Any] = [:]
    if let data = try? Data(contentsOf: url),
       let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        json = existing
    }

    var tokens = (json["tokens"] as? [String: Any]) ?? [:]
    tokens["access_token"] = credential.accessToken
    tokens["refresh_token"] = credential.refreshToken
    if let idToken = credential.idToken { tokens["id_token"] = idToken }
    if let accountID = credential.accountID { tokens["account_id"] = accountID }
    json["tokens"] = tokens
    json["last_refresh"] = ISO8601DateFormatter().string(from: Date())

    let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}
```

Add to `CodexTokenRefresher` in `Climeter/CodexAPIService.swift`:

```swift
static func refresh(_ credential: CodexCredential) async throws -> CodexCredential {
    guard !credential.refreshToken.isEmpty else { return credential }
    let request = try makeRefreshRequest(refreshToken: credential.refreshToken)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw CodexAPIError.invalidResponse }
    guard http.statusCode == 200 else {
        if http.statusCode == 401 { throw CodexAPIError.unauthorized }
        throw CodexAPIError.httpError(http.statusCode)
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CodexAPIError.invalidResponse
    }
    return CodexCredential(
        accessToken: json["access_token"] as? String ?? credential.accessToken,
        refreshToken: json["refresh_token"] as? String ?? credential.refreshToken,
        idToken: json["id_token"] as? String ?? credential.idToken,
        accountID: credential.accountID,
        lastRefresh: Date(),
        authMode: .chatGPT
    )
}
```

- [ ] **Step 5: Add files to project and run tests**

Modify `Climeter.xcodeproj/project.pbxproj` so the new coordinator file is in the app target and its tests are in the test target.

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: PASS for `CodexUsageRefreshCoordinatorTests`.

- [ ] **Step 6: Commit**

```bash
git add Climeter/CodexUsageRefreshCoordinator.swift Climeter/CodexCredentialStore.swift Climeter/CodexAPIService.swift ClimeterTests/CodexUsageRefreshCoordinatorTests.swift Climeter.xcodeproj/project.pbxproj
git commit -m "feat: add codex usage refresh coordinator"
```

---

### Task 6: Wire Codex State Into ProfileManager

**Files:**
- Modify: `Climeter/ProfileManager.swift`
- Modify: `Climeter/ProfileStore.swift`

- [ ] **Step 1: Add Codex persistence helpers**

In `Climeter/ProfileStore.swift`, add:

```swift
private static let codexEnabledKey = "codexEnabled"

static func loadCodexEnabled() -> Bool {
    UserDefaults.standard.object(forKey: codexEnabledKey) as? Bool ?? true
}

static func saveCodexEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: codexEnabledKey)
}
```

- [ ] **Step 2: Add Codex published state**

In `Climeter/ProfileManager.swift`, add properties near existing `@Published` fields:

```swift
@Published var codexUsageData: UsageData?
@Published var codexErrorMessage: String?
@Published var codexLastSuccessAt: Date?
@Published var codexEnabled: Bool = true {
    didSet {
        ProfileStore.saveCodexEnabled(codexEnabled)
        if codexEnabled {
            codexCoordinator.startPolling()
        } else {
            codexCoordinator.stopPolling()
            codexUsageData = nil
            codexErrorMessage = nil
            codexLastSuccessAt = nil
        }
    }
}

private let codexCoordinator = CodexUsageRefreshCoordinator()
private var codexCancellables: [AnyCancellable] = []
```

- [ ] **Step 3: Initialize and bind Codex coordinator**

In `ProfileManager.init()`, after loading Claude settings, add:

```swift
codexEnabled = ProfileStore.loadCodexEnabled()
setupCodexCoordinator()
if codexEnabled {
    codexCoordinator.startPolling()
}
```

Add this method to `ProfileManager`:

```swift
private func setupCodexCoordinator() {
    codexCancellables = [
        codexCoordinator.$usageData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in self?.codexUsageData = data },
        codexCoordinator.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.codexErrorMessage = message },
        codexCoordinator.$lastSuccessAt
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in self?.codexLastSuccessAt = date }
    ]
}
```

- [ ] **Step 4: Refresh and teardown Codex with existing lifecycle**

In `ProfileManager.refresh()`, append:

```swift
if codexEnabled {
    codexCoordinator.refresh()
}
```

In sleep handling, call:

```swift
self.codexCoordinator.stopPolling()
```

In `resumeAfterWake()`, after Claude coordinators restart, call:

```swift
if codexEnabled {
    codexCoordinator.startPolling()
}
```

In `deinit`, call:

```swift
codexCoordinator.stopPolling()
```

- [ ] **Step 5: Build**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add Climeter/ProfileManager.swift Climeter/ProfileStore.swift
git commit -m "feat: wire codex usage state"
```

---

### Task 7: Render Codex In Popover And Settings

**Files:**
- Modify: `Climeter/PopoverView.swift`
- Modify: `Climeter/SettingsView.swift`

- [ ] **Step 1: Add Codex card to popover**

In `Climeter/PopoverView.swift`, below the Claude profile card loop, add a separate Codex section:

```swift
if profileManager.codexEnabled || profileManager.codexUsageData != nil || profileManager.codexErrorMessage != nil {
    ProviderUsageCard(
        title: "Codex",
        badgeText: "OpenAI",
        usageData: profileManager.codexUsageData,
        errorMessage: profileManager.codexErrorMessage,
        lastSuccessAt: profileManager.codexLastSuccessAt,
        currentTime: currentTime
    )
    .padding(10)
    .background(
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
    )
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
}
```

- [ ] **Step 2: Extract reusable provider usage card**

In `Climeter/PopoverView.swift`, add:

```swift
struct ProviderUsageCard: View {
    let title: String
    let badgeText: String?
    let usageData: UsageData?
    let errorMessage: String?
    let lastSuccessAt: Date?
    let currentTime: Date

    private static let staleThreshold: TimeInterval = UsageRefreshCoordinator.baseInterval * 3

    private var staleAge: TimeInterval? {
        guard usageData != nil, let lastSuccessAt else { return nil }
        let age = currentTime.timeIntervalSince(lastSuccessAt)
        return age > Self.staleThreshold ? age : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.blue.opacity(0.12)))
                }
                Spacer()
                if let staleAge {
                    Text("stale \(ProfileCard.formatStaleAgeForProvider(staleAge))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }

            if let usageData {
                UsageRow(label: "Session", window: usageData.fiveHour, currentTime: currentTime)
                UsageRow(label: "Week", window: usageData.sevenDay, currentTime: currentTime)
            } else if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
```

Expose stale formatting from `ProfileCard` by changing its private formatter to:

```swift
static func formatStaleAgeForProvider(_ age: TimeInterval) -> String {
    formatStaleAge(age)
}
```

- [ ] **Step 3: Add Codex settings section**

In `Climeter/SettingsView.swift`, add this section after Launch at Login:

```swift
Section("Codex") {
    Toggle("Show Codex usage", isOn: $profileManager.codexEnabled)

    HStack {
        Text("Credentials")
        Spacer()
        Text(CodexCredentialStore.authFileURL().path)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    if let error = profileManager.codexErrorMessage {
        Text(error)
            .font(.caption)
            .foregroundColor(.secondary)
    } else if profileManager.codexUsageData != nil {
        Text("Connected")
            .font(.caption)
            .foregroundColor(.secondary)
    } else {
        Text("Run `codex login` if usage does not appear.")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
```

Increase the settings frame height from `400` to `470`.

- [ ] **Step 4: Build**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Climeter/PopoverView.swift Climeter/SettingsView.swift
git commit -m "feat: show codex usage in ui"
```

---

### Task 8: Final Verification And Manual Smoke Test

- [ ] **Step 1: Run full tests**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug test
```

Expected: TEST SUCCEEDED.

- [ ] **Step 2: Run debug build**

Run:

```bash
xcodebuild -scheme Climeter -configuration Debug build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Launch app for smoke test**

Run:

```bash
open ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/Climeter.app
```

Expected:

- Existing Claude usage still appears.
- Codex card appears when Codex is enabled.
- If Codex is logged in, Codex shows Session and Week usage.
- If Codex is not logged in, Codex shows "Run `codex login`".
- Menu bar icon behavior remains Claude-driven.

- [ ] **Step 4: Inspect logs for secrets**

Run:

```bash
tail -200 ~/Library/Logs/Climeter/climeter.log | rg -i "access_token|refresh_token|id_token|Bearer|OPENAI_API_KEY|sk-"
```

Expected: no matches.

---

## Completion Checklist

- [ ] `xcodebuild -scheme Climeter -configuration Debug test` succeeds.
- [ ] `xcodebuild -scheme Climeter -configuration Debug build` succeeds.
- [ ] Codex provider does not read `~/.codex/sessions`.
- [ ] Logs do not include tokens or raw auth JSON.
- [ ] Claude profile polling and auto-switch still work.
- [ ] Codex does not participate in Claude auto-switch.
- [ ] Menu bar icon remains Claude-driven.
