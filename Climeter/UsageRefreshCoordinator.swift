import Foundation
import SwiftUI

class UsageRefreshCoordinator: ObservableObject {
    @Published var usageData: UsageData?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    let profileID: UUID
    private let credentialProvider: () -> Credential?
    private let onCredentialRefreshed: ((Credential) -> Void)?
    private var timer: Timer?
    private let baseInterval: TimeInterval = 180.0
    private var currentInterval: TimeInterval = 180.0
    private let maxInterval: TimeInterval = 900.0

    private let onCredentialInvalid: (() -> Credential?)?

    init(profileID: UUID,
         credentialProvider: @escaping () -> Credential?,
         onCredentialRefreshed: ((Credential) -> Void)? = nil,
         onCredentialInvalid: (() -> Credential?)? = nil) {
        self.profileID = profileID
        self.credentialProvider = credentialProvider
        self.onCredentialRefreshed = onCredentialRefreshed
        self.onCredentialInvalid = onCredentialInvalid
    }

    func startPolling() {
        guard timer == nil else { return }
        // Small delay on first poll to avoid hitting rate limits on rapid restarts
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.scheduleNextPoll()
        }
    }

    private func scheduleNextPoll() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { [weak self] _ in
            self?.refresh()
            self?.scheduleNextPoll()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isLoading else { return }
        guard var credential = credentialProvider() else { return }

        isLoading = true

        Task { @MainActor in
            defer { self.isLoading = false }

            if credential.isExpired {
                do {
                    credential = try await ClaudeAPIService.refreshToken(credential)
                    self.onCredentialRefreshed?(credential)
                } catch {
                    // Refresh token may be stale — try CLI keychain for a fresh credential
                    if let fresh = self.onCredentialInvalid?() {
                        credential = fresh
                        if credential.isExpired {
                            do {
                                credential = try await ClaudeAPIService.refreshToken(credential)
                                self.onCredentialRefreshed?(credential)
                            } catch {
                                self.errorMessage = Self.describeError(error, context: "token refresh")
                                return
                            }
                        } else {
                            self.onCredentialRefreshed?(credential)
                        }
                    } else {
                        self.errorMessage = Self.describeError(error, context: "token refresh")
                        return
                    }
                }
            }

            do {
                let fetchedData = try await ClaudeAPIService.fetchUsage(credential: credential)
                self.usageData = fetchedData
                self.errorMessage = nil
                self.resetBackoff()
            } catch {
                self.handleFetchError(error)
            }
        }
    }

    private func handleFetchError(_ error: Error) {
        let is429 = (error as? ClaudeAPIError).map {
            if case .httpError(429) = $0 { return true }
            return false
        } ?? false

        if is429 {
            currentInterval = min(currentInterval * 2, maxInterval)
            scheduleNextPoll()
        }

        if usageData == nil {
            errorMessage = Self.describeError(error, context: "fetch")
        }
    }

    private func resetBackoff() {
        guard currentInterval != baseInterval else { return }
        currentInterval = baseInterval
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
