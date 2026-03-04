import Foundation
import SwiftUI
import Combine

class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var allUsageData: [UUID: UsageData] = [:]
    @Published var allErrors: [UUID: String] = [:]
    @Published var cliActiveProfileID: UUID?

    private var coordinators: [UUID: UsageRefreshCoordinator] = [:]
    private var cancellables: [UUID: [AnyCancellable]] = [:]
    private let autoSwitchThreshold: Double = 95.0
    private var lastAutoSwitchDate: Date?

    // Convenience for menu bar: usage data for CLI-active profile
    var cliActiveUsageData: UsageData? {
        guard let id = cliActiveProfileID else { return nil }
        return allUsageData[id]
    }

    var cliActiveProfile: Profile? {
        guard let id = cliActiveProfileID else { return nil }
        return profiles.first { $0.id == id }
    }

    var hasAnyAuthenticated: Bool {
        profiles.contains { ProfileStore.loadCredentialModel(for: $0.id) != nil }
    }

    init() {
        loadProfiles()
        loadCLIActiveProfileID()
        setupAllCoordinators()

        // Read CLI keychain on background thread to avoid blocking the UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let cliCredential = ClaudeCodeSyncService.readCLICredential()
            DispatchQueue.main.async {
                self.handleCLICredential(cliCredential)
            }
        }
    }

    // MARK: - Initialization

    private func loadProfiles() {
        profiles = ProfileStore.loadProfiles()
        if profiles.isEmpty {
            let defaultProfile = Profile(name: "Default")
            profiles = [defaultProfile]
            ProfileStore.saveProfiles(profiles)
        }
    }

    private func loadCLIActiveProfileID() {
        if let savedID = ProfileStore.loadCLIActiveProfileID(),
           profiles.contains(where: { $0.id == savedID }) {
            cliActiveProfileID = savedID
        }
    }

    private func handleCLICredential(_ cliCredential: Credential?) {
        // Skip if we already have a profile with credentials
        let hasStoredCredentials = profiles.contains { ProfileStore.loadCredentialModel(for: $0.id) != nil }
        if hasStoredCredentials { return }

        guard let cliCredential else { return }

        let target = profiles.first { ProfileStore.loadCredentialModel(for: $0.id) == nil }
            ?? profiles[0]
        try? ProfileStore.saveCredentialModel(cliCredential, for: target.id)
        cliActiveProfileID = target.id
        ProfileStore.saveCLIActiveProfileID(target.id)
        setupCoordinator(for: target.id)
    }

    // MARK: - Usage Coordinators

    private func setupAllCoordinators() {
        for profile in profiles {
            guard ProfileStore.loadCredentialModel(for: profile.id) != nil else { continue }
            setupCoordinator(for: profile.id)
        }
    }

    private func setupCoordinator(for profileID: UUID) {
        // Don't create duplicates
        guard coordinators[profileID] == nil else { return }

        let coordinator = UsageRefreshCoordinator(
            profileID: profileID,
            credentialProvider: {
                ProfileStore.loadCredentialModel(for: profileID)
            },
            onCredentialRefreshed: { [weak self] refreshed in
                try? ProfileStore.saveCredentialModel(refreshed, for: profileID)
                // If this is the CLI-active profile, also update system Keychain
                if self?.cliActiveProfileID == profileID {
                    ClaudeCodeSyncService.writeCLICredential(refreshed)
                }
            }
        )

        let usageSink = coordinator.$usageData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                self?.allUsageData[profileID] = data
                self?.checkAutoSwitch()
            }
        let errorSink = coordinator.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.allErrors[profileID] = msg
            }
        cancellables[profileID] = [usageSink, errorSink]
        coordinators[profileID] = coordinator
        coordinator.startPolling()
    }

    private func teardownCoordinator(for profileID: UUID) {
        coordinators[profileID]?.stopPolling()
        coordinators.removeValue(forKey: profileID)
        cancellables.removeValue(forKey: profileID)
        allUsageData.removeValue(forKey: profileID)
        allErrors.removeValue(forKey: profileID)
    }

    // MARK: - Auto-Switch

    private func checkAutoSwitch() {
        guard let activeID = cliActiveProfileID,
              let activeData = allUsageData[activeID],
              activeData.fiveHour.utilization >= autoSwitchThreshold else { return }

        // Cooldown: don't flip-flop more than once per 60s
        if let last = lastAutoSwitchDate, Date().timeIntervalSince(last) < 60 { return }

        // Find first authenticated profile under threshold
        let candidate = profiles.first { profile in
            profile.id != activeID
                && ProfileStore.loadCredentialModel(for: profile.id) != nil
                && (allUsageData[profile.id]?.fiveHour.utilization ?? 100) < autoSwitchThreshold
        }

        guard let target = candidate else { return }
        lastAutoSwitchDate = Date()
        activateForCLI(profileID: target.id)
    }

    // MARK: - Public API

    func refresh() {
        for coordinator in coordinators.values {
            coordinator.refresh()
        }
        // Re-sync CLI credential in background (won't block UI)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cliCredential = ClaudeCodeSyncService.readCLICredential()
            DispatchQueue.main.async {
                self?.syncCLICredential(cliCredential)
            }
        }
    }

    private func syncCLICredential(_ cliCredential: Credential?) {
        guard let cliCredential else { return }

        for profile in profiles {
            if let stored = ProfileStore.loadCredentialModel(for: profile.id),
               stored.accessToken == cliCredential.accessToken {
                if cliActiveProfileID != profile.id {
                    cliActiveProfileID = profile.id
                    ProfileStore.saveCLIActiveProfileID(profile.id)
                }
                return
            }
        }

        // New account — create profile
        let newProfile = Profile(name: "Account \(profiles.count + 1)")
        profiles.append(newProfile)
        ProfileStore.saveProfiles(profiles)

        try? ProfileStore.saveCredentialModel(cliCredential, for: newProfile.id)
        cliActiveProfileID = newProfile.id
        ProfileStore.saveCLIActiveProfileID(newProfile.id)

        setupCoordinator(for: newProfile.id)
    }

    func activateForCLI(profileID: UUID) {
        guard let credential = ProfileStore.loadCredentialModel(for: profileID) else { return }
        ClaudeCodeSyncService.writeCLICredential(credential)
        cliActiveProfileID = profileID
        ProfileStore.saveCLIActiveProfileID(profileID)
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
        ProfileStore.saveProfiles(profiles)
    }

    func deleteProfile(id: UUID) {
        guard profiles.count > 1 else { return }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }

        teardownCoordinator(for: id)

        if cliActiveProfileID == id {
            cliActiveProfileID = profiles.first(where: { $0.id != id })?.id
            ProfileStore.saveCLIActiveProfileID(cliActiveProfileID)
        }

        profiles.remove(at: index)
        ProfileStore.saveProfiles(profiles)
        try? ProfileStore.deleteCredential(for: id)
    }

    func removeCredential(for profileID: UUID) {
        teardownCoordinator(for: profileID)
        try? ProfileStore.deleteCredential(for: profileID)
    }

    deinit {
        for coordinator in coordinators.values {
            coordinator.stopPolling()
        }
    }
}
