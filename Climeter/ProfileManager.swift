import Foundation
import SwiftUI

class ProfileManager: ObservableObject {
    @Published var activeProfile: Profile?
    @Published var isAuthenticated: Bool = false
    @Published var usageData: UsageData?

    @Published var profiles: [Profile] = []
    private var usageCoordinator: UsageRefreshCoordinator?

    init() {
        loadProfiles()
        setupActiveProfile()
        syncCLICredentials()
        updateAuthenticationStatus()
        setupUsageCoordinator()
    }

    private func loadProfiles() {
        profiles = ProfileStore.loadProfiles()

        // If no profiles exist, create a default profile
        if profiles.isEmpty {
            let defaultProfile = Profile(name: "Default", autoStartSession: false)
            profiles = [defaultProfile]
            ProfileStore.saveProfiles(profiles)
            ProfileStore.saveActiveProfileID(defaultProfile.id)
        }
    }

    private func setupActiveProfile() {
        // Try to load saved active profile ID
        if let activeID = ProfileStore.loadActiveProfileID(),
           let profile = profiles.first(where: { $0.id == activeID }) {
            activeProfile = profile
        } else if let firstProfile = profiles.first {
            // Fallback to first profile if no active ID saved
            activeProfile = firstProfile
            ProfileStore.saveActiveProfileID(firstProfile.id)
        }
    }

    func syncCLICredentials() {
        guard let profile = activeProfile else { return }

        // Try to read CLI credential from system keychain
        if let cliCredential = ClaudeCodeSyncService.readCLICredential() {
            // Store the credential for the active profile
            do {
                try ProfileStore.saveCredential(cliCredential, for: profile.id)
                updateAuthenticationStatus()
            } catch {
                // Silent failure - credential sync failed but app continues
            }
        }
    }

    private func updateAuthenticationStatus() {
        guard let profile = activeProfile else {
            isAuthenticated = false
            return
        }

        do {
            let credential = try ProfileStore.loadCredential(for: profile.id)
            isAuthenticated = credential != nil
        } catch {
            isAuthenticated = false
        }
    }

    private func setupUsageCoordinator() {
        // Create coordinator with credential provider
        usageCoordinator = UsageRefreshCoordinator { [weak self] in
            guard let self = self,
                  let profile = self.activeProfile else {
                return nil
            }

            return try? ProfileStore.loadCredential(for: profile.id)
        }

        // Observe usage data changes from coordinator
        usageCoordinator?.$usageData
            .assign(to: &$usageData)

        // Start polling if authenticated
        if isAuthenticated {
            usageCoordinator?.startPolling()
        }
    }

    func refresh() {
        usageCoordinator?.refresh()
    }

    func createProfile(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newProfile = Profile(name: trimmed)
        profiles.append(newProfile)
        ProfileStore.saveProfiles(profiles)
    }

    func renameProfile(id: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        profiles[index].name = trimmed
        if activeProfile?.id == id {
            activeProfile = profiles[index]
        }
        ProfileStore.saveProfiles(profiles)
    }

    func deleteProfile(id: UUID) {
        guard profiles.count > 1 else { return }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        if activeProfile?.id == id {
            guard let newActiveProfile = profiles.first(where: { $0.id != id }) else { return }
            switchProfile(to: newActiveProfile.id)
        }

        profiles.remove(at: index)
        ProfileStore.saveProfiles(profiles)

        do {
            try ProfileStore.deleteCredential(for: id)
        } catch {}
    }

    func switchProfile(to id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        guard activeProfile?.id != id else { return }

        usageCoordinator?.stopPolling()
        usageData = nil

        activeProfile = profile
        ProfileStore.saveActiveProfileID(id)

        syncCLICredentials()
        updateAuthenticationStatus()

        if isAuthenticated {
            usageCoordinator?.startPolling()
        }
    }
}
