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
    private let powerMonitor = PowerStateMonitor()
    private var hasResumedSinceLastSleep = false

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

    private func setupPowerMonitor() {
        powerMonitor.onSleep = { [weak self] in
            guard let self else { return }
            self.hasResumedSinceLastSleep = false
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
        guard !hasResumedSinceLastSleep else { return }
        hasResumedSinceLastSleep = true
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

    // MARK: - Usage Coordinators

    private func setupAllCoordinators() {
        for profile in profiles where authenticatedProfileIDs.contains(profile.id) {
            setupCoordinator(for: profile.id)
        }
    }

    private func setupCoordinator(for profileID: UUID) {
        // Don't create duplicates
        guard coordinators[profileID] == nil else { return }
        Log.profiles.info("setupCoordinator for \(profileID)")

        let coordinator = UsageRefreshCoordinator(
            profileID: profileID,
            credentialProvider: { [weak self] in
                self?.cachedCredentials[profileID]
            },
            onCredentialRefreshed: { [weak self] refreshed in
                Log.profiles.info("[\(profileID)] credential refreshed, saving to app keychain...")
                self?.cachedCredentials[profileID] = refreshed
                try? ProfileStore.saveCredentialModel(refreshed, for: profileID)
                if self?.cliActiveProfileID == profileID {
                    Log.profiles.info("[\(profileID)] is CLI-active, writing back to CLI keychain...")
                    ClaudeCodeSyncService.writeCLICredential(refreshed)
                }
            },
            syncCLICredential: { [weak self] in
                let isCLIActive = self?.cliActiveProfileID == profileID
                guard isCLIActive else {
                    Log.coordinator.debug("[\(profileID)] skipping CLI sync — not CLI-active profile")
                    return
                }
                Log.coordinator.info("[\(profileID)] reading CLI keychain for sync...")
                guard let fresh = ClaudeCodeSyncService.readCLICredential() else {
                    Log.coordinator.info("[\(profileID)] CLI keychain returned nil")
                    return
                }
                guard fresh.refreshToken != self?.cachedCredentials[profileID]?.refreshToken else {
                    Log.coordinator.debug("[\(profileID)] CLI credential unchanged (same refresh token)")
                    return
                }
                Log.coordinator.info("[\(profileID)] CLI credential has newer refresh token, updating cache")
                self?.cachedCredentials[profileID] = fresh
                try? ProfileStore.saveCredentialModel(fresh, for: profileID)
            },
            onAutoStart: { [weak self] credential in
                guard self?.cliActiveProfileID == profileID else { return }
                Task {
                    await ClaudeAPIService.startSession(credential: credential)
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
        Log.profiles.info("autoSwitch: \(activeID) at \(activeData.fiveHour.utilization)% -> switching to \(target.id)")
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
        Log.profiles.info("activateForCLI: switching to \(profileID), writing to CLI keychain...")
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
