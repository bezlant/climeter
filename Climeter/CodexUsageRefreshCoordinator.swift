import Foundation
import SwiftUI

enum CodexUsageRefreshError: Error, Equatable {
    case apiKeyMode
}

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
