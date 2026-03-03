import Foundation
import SwiftUI

class UsageRefreshCoordinator: ObservableObject {
    @Published var usageData: UsageData?
    @Published var isLoading: Bool = false

    private let credentialProvider: () -> String?
    private var timer: Timer?
    private let refreshInterval: TimeInterval = 60.0 // 60 seconds for now

    init(credentialProvider: @escaping () -> String?) {
        self.credentialProvider = credentialProvider
    }

    func startPolling() {
        // Don't start if already running
        guard timer == nil else { return }

        // Do an immediate fetch
        refresh()

        // Set up recurring timer
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        // Skip if already loading
        guard !isLoading else { return }

        // Get credential
        guard let credential = credentialProvider() else {
            // No credential available, can't fetch
            return
        }

        isLoading = true

        Task { @MainActor in
            do {
                let fetchedData = try await ClaudeAPIService.fetchUsage(credential: credential)
                self.usageData = fetchedData
            } catch {
                // Silent failure - keep old data
                // In production, could log error or expose it via @Published error property
            }

            self.isLoading = false
        }
    }

    deinit {
        stopPolling()
    }
}
