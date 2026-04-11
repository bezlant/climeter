import Foundation
import SwiftUI

class UsageRefreshCoordinator: ObservableObject {
    @Published var usageData: UsageData?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastSuccessAt: Date?

    let profileID: UUID
    private let credentialProvider: () -> Credential?
    private let onCredentialRefreshed: ((Credential) -> Void)?
    private var timer: Timer?
    static let baseInterval: TimeInterval = 180.0
    private var currentInterval: TimeInterval = UsageRefreshCoordinator.baseInterval
    // IMPORTANT: max backoff must stay high — Anthropic's /api/oauth/usage
    // endpoint rate-limits aggressively (see anthropics/claude-code#31637)
    // and stays locked out for 30+ minutes even at 5-minute retry intervals.
    private let maxInterval: TimeInterval = 900.0

    /// Reads the CLI keychain and updates the credential cache
    /// if a newer credential is available.
    private let syncCLICredential: (() -> Void)?

    private var lastAutoStartResetTime: Date?
    private let onAutoStart: ((Credential) -> Void)?

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

    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.scheduleNextPoll()
        }
    }

    private func scheduleNextPoll() {
        timer?.invalidate()
        // Add ±10% jitter to avoid two coordinators staying phase-locked
        // and colliding on every poll cycle.
        let jitter = Double.random(in: 0.9...1.1)
        let interval = currentInterval * jitter
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.scheduleNextPoll()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isLoading else {
            Log.coordinator.debug("[\(self.profileID)] refresh skipped — already loading")
            return
        }

        Log.coordinator.info("[\(self.profileID)] poll cycle start (interval: \(self.currentInterval)s)")

        guard var credential = credentialProvider() else {
            Log.coordinator.warning("[\(self.profileID)] no credential available, skipping poll")
            return
        }

        let expiresIn = credential.expiresAt.timeIntervalSinceNow
        Log.coordinator.info("[\(self.profileID)] token expires in \(Int(expiresIn))s, isExpired=\(credential.isExpired)")

        isLoading = true

        Task { @MainActor in
            defer { self.isLoading = false }

            if credential.isExpired {
                Log.coordinator.info("[\(self.profileID)] token expired, starting recovery...")
                do {
                    credential = try await self.recoverCredential(credential)
                    Log.coordinator.info("[\(self.profileID)] token recovery succeeded")
                } catch {
                    Log.coordinator.error("[\(self.profileID)] token recovery failed: \(error)")
                    self.errorMessage = Self.describeError(error, context: "token refresh")
                    return
                }
            }

            do {
                let fetchedData = try await ClaudeAPIService.fetchUsage(credential: credential)
                Log.coordinator.info("[\(self.profileID)] usage fetch OK — 5h: \(fetchedData.fiveHour.utilization)%")
                self.usageData = fetchedData
                self.errorMessage = nil
                self.lastSuccessAt = Date()
                self.checkAutoStart(credential: credential, usage: fetchedData)
                self.stepDownBackoff()
            } catch {
                // Access token rejected server-side (e.g. revoked by a new
                // /login between the proactive sync and this API call) —
                // recover and retry once.
                guard case .httpError(401) = error as? ClaudeAPIError else {
                    Log.coordinator.error("[\(self.profileID)] usage fetch failed: \(error)")
                    self.handleFetchError(error)
                    return
                }
                Log.coordinator.warning("[\(self.profileID)] got 401, attempting recovery...")
                do {
                    credential = try await self.recoverCredential(credential)
                    let fetchedData = try await ClaudeAPIService.fetchUsage(credential: credential)
                    Log.coordinator.info("[\(self.profileID)] retry after 401 succeeded — 5h: \(fetchedData.fiveHour.utilization)%")
                    self.usageData = fetchedData
                    self.errorMessage = nil
                    self.lastSuccessAt = Date()
                    self.checkAutoStart(credential: credential, usage: fetchedData)
                    self.stepDownBackoff()
                } catch {
                    Log.coordinator.error("[\(self.profileID)] retry after 401 failed: \(error)")
                    self.handleFetchError(error)
                }
            }
        }
    }

    /// Attempt to refresh the credential. On failure, sync from CLI keychain
    /// and retry with the fresh credential if one was found.
    private func recoverCredential(_ credential: Credential) async throws -> Credential {
        do {
            Log.coordinator.info("[\(self.profileID)] attempting token refresh via API...")
            let refreshed = try await ClaudeAPIService.refreshToken(credential)
            Log.coordinator.info("[\(self.profileID)] token refresh succeeded, writing back...")
            onCredentialRefreshed?(refreshed)
            return refreshed
        } catch {
            Log.coordinator.warning("[\(self.profileID)] token refresh failed: \(error) — trying CLI keychain fallback")
            // Refresh token may be stale — read CLI keychain for a newer one.
            // This is the only place we read the CLI keychain during polling
            // (not every cycle) to avoid repeated keychain password prompts.
            syncCLICredential?()
            guard let fresh = credentialProvider(),
                  fresh.refreshToken != credential.refreshToken else {
                Log.coordinator.error("[\(self.profileID)] CLI keychain had no newer credential, giving up")
                throw error
            }
            Log.coordinator.info("[\(self.profileID)] found different refresh token from CLI keychain")
            if fresh.isExpired {
                Log.coordinator.info("[\(self.profileID)] CLI credential also expired, refreshing it...")
                let refreshed = try await ClaudeAPIService.refreshToken(fresh)
                onCredentialRefreshed?(refreshed)
                return refreshed
            }
            Log.coordinator.info("[\(self.profileID)] using fresh CLI credential directly")
            onCredentialRefreshed?(fresh)
            return fresh
        }
    }

    private func checkAutoStart(credential: Credential, usage: UsageData) {
        guard onAutoStart != nil,
              usage.fiveHour.utilization == 0 else {
            lastAutoStartResetTime = nil
            return
        }
        guard let resetTime = usage.fiveHour.resetsAt else { return }
        guard lastAutoStartResetTime != resetTime else { return }
        lastAutoStartResetTime = resetTime
        onAutoStart?(credential)
    }

    private func handleFetchError(_ error: Error) {
        let is429 = (error as? ClaudeAPIError).map {
            if case .httpError(429) = $0 { return true }
            return false
        } ?? false

        if is429 {
            currentInterval = min(currentInterval * 2, maxInterval)
            Log.coordinator.info("[\(self.profileID)] backoff increased → \(self.currentInterval)s")
            scheduleNextPoll()
        }

        if usageData == nil {
            errorMessage = Self.describeError(error, context: "fetch")
        }
    }

    /// Halve the polling interval after a successful fetch instead of jumping
    /// straight back to baseInterval. The /api/oauth/usage endpoint frequently
    /// returns 429 again immediately when we drop back to the base interval
    /// after a single success, so we step down gradually.
    private func stepDownBackoff() {
        guard currentInterval > Self.baseInterval else { return }
        currentInterval = max(currentInterval / 2, Self.baseInterval)
        Log.coordinator.info("[\(self.profileID)] backoff step-down → \(self.currentInterval)s")
        scheduleNextPoll()
    }

    private static func describeError(_ error: Error, context: String) -> String {
        guard let apiError = error as? ClaudeAPIError else {
            return "Network error"
        }
        switch apiError {
        case .httpError(401), .tokenRefreshFailed(401):
            return "Session expired — run /login"
        case .tokenRefreshFailed(400):
            return "Token invalid — run /login"
        case .httpError(429):
            return "Rate limited — retrying soon"
        case .httpError(let code), .tokenRefreshFailed(let code):
            return "HTTP \(code)"
        case .invalidResponse:
            return "Bad response"
        case .decodingError:
            return "Unexpected data format"
        case .invalidCredential:
            return "Invalid credential"
        }
    }

    deinit {
        stopPolling()
    }
}
