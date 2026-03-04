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
    private let refreshInterval: TimeInterval = 60.0

    init(profileID: UUID,
         credentialProvider: @escaping () -> Credential?,
         onCredentialRefreshed: ((Credential) -> Void)? = nil) {
        self.profileID = profileID
        self.credentialProvider = credentialProvider
        self.onCredentialRefreshed = onCredentialRefreshed
    }

    func startPolling() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
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
                    self.errorMessage = Self.describeError(error, context: "token refresh")
                    return
                }
            }

            do {
                let fetchedData = try await ClaudeAPIService.fetchUsage(credential: credential)
                self.usageData = fetchedData
                self.errorMessage = nil
            } catch {
                // Keep old data if we have it, but show error if we don't
                if self.usageData == nil {
                    self.errorMessage = Self.describeError(error, context: "fetch")
                }
            }
        }
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
