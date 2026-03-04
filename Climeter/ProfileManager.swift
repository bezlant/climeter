import Foundation
import SwiftUI
import Combine

class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var allUsageData: [UUID: UsageData] = [:]
    @Published var allErrors: [UUID: String] = [:]
    @Published var cliActiveProfileID: UUID?
    @Published private(set) var authenticatedProfileIDs: Set<UUID> = []

    private var coordinators: [UUID: UsageRefreshCoordinator] = [:]
    private var cancellables: [UUID: [AnyCancellable]] = [:]
    private var cachedCredentials: [UUID: Credential] = [:]
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
        !authenticatedProfileIDs.isEmpty
    }

    var authenticatedProfiles: [Profile] {
        profiles.filter { authenticatedProfileIDs.contains($0.id) }
    }

    init() {
        loadProfiles()
        refreshAuthenticatedIDs()
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

    private func refreshAuthenticatedIDs() {
        cachedCredentials.removeAll()
        for profile in profiles {
            if let credential = ProfileStore.loadCredentialModel(for: profile.id) {
                cachedCredentials[profile.id] = credential
            }
        }
        authenticatedProfileIDs = Set(cachedCredentials.keys)
    }

    func cachedCredential(for profileID: UUID) -> Credential? {
        cachedCredentials[profileID]
    }

    func updateCachedCredential(_ credential: Credential, for profileID: UUID) {
        cachedCredentials[profileID] = credential
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
        if hasAnyAuthenticated { return }

        guard let cliCredential else { return }

        let target = profiles.first { !authenticatedProfileIDs.contains($0.id) }
            ?? profiles[0]
        try? ProfileStore.saveCredentialModel(cliCredential, for: target.id)
        cliActiveProfileID = target.id
        ProfileStore.saveCLIActiveProfileID(target.id)
        refreshAuthenticatedIDs()
        setupCoordinator(for: target.id)
    }

    // MARK: - Usage Coordinators

    private func setupAllCoordinators() {
        for profile in profiles where authenticatedProfileIDs.contains(profile.id) {
            setupCoordinator(for: profile.id)
        }
    }

    private func setupCoordinator(for profileID: UUID) {
        // Don't create duplicates
        guard coordinators[profileID] == nil else { return }

        let coordinator = UsageRefreshCoordinator(
            profileID: profileID,
            credentialProvider: { [weak self] in
                self?.cachedCredentials[profileID]
            },
            onCredentialRefreshed: { [weak self] refreshed in
                self?.cachedCredentials[profileID] = refreshed
                try? ProfileStore.saveCredentialModel(refreshed, for: profileID)
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
                && authenticatedProfileIDs.contains(profile.id)
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
    }

    private func syncCLICredential(_ cliCredential: Credential?) {
        guard let cliCredential else { return }

        for profile in profiles {
            if let stored = cachedCredentials[profile.id],
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
        refreshAuthenticatedIDs()

        setupCoordinator(for: newProfile.id)
    }

    func activateForCLI(profileID: UUID) {
        guard let credential = cachedCredentials[profileID] else { return }
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
        refreshAuthenticatedIDs()
    }

    func removeCredential(for profileID: UUID) {
        teardownCoordinator(for: profileID)
        try? ProfileStore.deleteCredential(for: profileID)
        refreshAuthenticatedIDs()
    }

    deinit {
        for coordinator in coordinators.values {
            coordinator.stopPolling()
        }
    }
}
