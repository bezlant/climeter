import Foundation
import SwiftUI
import Combine

class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var allUsageData: [UUID: UsageData] = [:]
    @Published var allErrors: [UUID: String] = [:]
    @Published var cliActiveProfileID: UUID?
    @Published private(set) var authenticatedProfileIDs: Set<UUID> = []

    @Published var autoSwitchEnabled: Bool = false {
        didSet { ProfileStore.saveAutoSwitchEnabled(autoSwitchEnabled) }
    }
    @Published var autoSwitchThreshold: Double = 95.0 {
        didSet { ProfileStore.saveAutoSwitchThreshold(autoSwitchThreshold) }
    }

    private var coordinators: [UUID: UsageRefreshCoordinator] = [:]
    private var cancellables: [UUID: [AnyCancellable]] = [:]
    private var cachedCredentials: [UUID: Credential] = [:]
    private var lastAutoSwitchDate: Date?
    private let powerMonitor = PowerStateMonitor()
    private var hasResumedSinceLastSleep = false
    private var cliMonitorTimer: Timer?

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
        autoSwitchEnabled = ProfileStore.loadAutoSwitchEnabled()
        autoSwitchThreshold = ProfileStore.loadAutoSwitchThreshold()
        Log.profiles.info("init: \(self.profiles.count) profiles, \(self.authenticatedProfileIDs.count) authenticated, cliActive=\(self.cliActiveProfileID?.uuidString ?? "none")")
        setupAllCoordinators()
        backfillAccountUUIDs()
        startCLIMonitoring()
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

    // MARK: - CLI Account Detection

    private func startCLIMonitoring() {
        // Initial check after short delay (gives backfill time)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.detectCLIAccountChange()
        }
        cliMonitorTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.detectCLIAccountChange()
        }
    }

    private func stopCLIMonitoring() {
        cliMonitorTimer?.invalidate()
        cliMonitorTimer = nil
    }

    private func detectCLIAccountChange() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let cliCredential = ClaudeCodeSyncService.readCLICredential()
            DispatchQueue.main.async {
                self?.processCLICredential(cliCredential)
            }
        }
    }

    private func processCLICredential(_ cliCredential: Credential?) {
        guard let cliCredential else { return }

        // Quick check: if tokens match CLI-active profile, nothing changed
        if let activeID = cliActiveProfileID,
           let cached = cachedCredentials[activeID] {
            if cached.refreshToken == cliCredential.refreshToken
                || cached.accessToken == cliCredential.accessToken {
                return
            }
        }

        Log.profiles.info("detectCLI: credential changed, identifying account...")

        Task {
            await self.identifyAndSyncAccount(cliCredential)
        }
    }

    @MainActor
    private func identifyAndSyncAccount(_ cliCredential: Credential) async {
        var credential = cliCredential

        // Refresh expired token before identifying account
        if credential.isExpired {
            Log.profiles.info("detectCLI: token expired, refreshing first...")
            if let refreshed = try? await ClaudeAPIService.refreshToken(credential) {
                credential = refreshed
            }
        }

        guard let apiProfile = try? await ClaudeAPIService.fetchProfile(credential: credential) else {
            Log.profiles.warning("detectCLI: fetchProfile failed")
            // Fallback: bootstrap only (no authenticated profiles yet)
            if !hasAnyAuthenticated {
                let target = profiles.first { !authenticatedProfileIDs.contains($0.id) } ?? profiles[0]
                saveAndActivate(credential: credential, profileID: target.id)
            }
            return
        }

        credential.accountUUID = apiProfile.uuid
        Log.profiles.info("detectCLI: account=\(apiProfile.uuid) name=\(apiProfile.displayName)")

        // Match by accountUUID
        for profile in profiles {
            if let stored = cachedCredentials[profile.id],
               stored.accountUUID == apiProfile.uuid {
                Log.profiles.info("detectCLI: matched existing profile '\(profile.name)'")
                saveAndActivate(credential: credential, profileID: profile.id)
                return
            }
        }

        // Eagerly resolve profiles with nil accountUUID (migration/backfill race)
        for profile in profiles {
            guard let stored = cachedCredentials[profile.id],
                  stored.accountUUID == nil else { continue }
            Log.profiles.info("detectCLI: resolving accountUUID for '\(profile.name)'...")
            if let storedProfile = try? await ClaudeAPIService.fetchProfile(credential: stored) {
                var updated = stored
                updated.accountUUID = storedProfile.uuid
                cachedCredentials[profile.id] = updated
                try? ProfileStore.saveCredentialModel(updated, for: profile.id)
                if storedProfile.uuid == apiProfile.uuid {
                    Log.profiles.info("detectCLI: resolved match → '\(profile.name)'")
                    saveAndActivate(credential: credential, profileID: profile.id)
                    return
                }
            }
        }

        // New account — assign to first unauthenticated profile or create one
        if let target = profiles.first(where: { !authenticatedProfileIDs.contains($0.id) }) {
            Log.profiles.info("detectCLI: new account → unauthenticated profile '\(target.name)'")
            saveAndActivate(credential: credential, profileID: target.id)
        } else {
            let newProfile = Profile(name: apiProfile.displayName)
            profiles.append(newProfile)
            ProfileStore.saveProfiles(profiles)
            Log.profiles.info("detectCLI: new account → created profile '\(apiProfile.displayName)'")
            saveAndActivate(credential: credential, profileID: newProfile.id)
        }
    }

    private func saveAndActivate(credential: Credential, profileID: UUID) {
        cachedCredentials[profileID] = credential
        try? ProfileStore.saveCredentialModel(credential, for: profileID)
        refreshAuthenticatedIDs()
        if cliActiveProfileID != profileID {
            cliActiveProfileID = profileID
            ProfileStore.saveCLIActiveProfileID(profileID)
        }
        if coordinators[profileID] == nil {
            setupCoordinator(for: profileID)
        }
    }

    /// Backfill accountUUID for profiles that were created before account detection
    private func backfillAccountUUIDs() {
        let needsBackfill = profiles.filter { p in
            guard let cred = cachedCredentials[p.id] else { return false }
            return cred.accountUUID == nil
        }
        guard !needsBackfill.isEmpty else { return }
        Log.profiles.info("backfill: \(needsBackfill.count) profiles need accountUUID")

        for profile in needsBackfill {
            guard let credential = cachedCredentials[profile.id] else { continue }
            Task {
                guard let apiProfile = try? await ClaudeAPIService.fetchProfile(credential: credential) else {
                    Log.profiles.error("backfill: failed for '\(profile.name)'")
                    return
                }
                await MainActor.run {
                    var updated = self.cachedCredentials[profile.id] ?? credential
                    updated.accountUUID = apiProfile.uuid
                    self.cachedCredentials[profile.id] = updated
                    try? ProfileStore.saveCredentialModel(updated, for: profile.id)
                    Log.profiles.info("backfill: set accountUUID for '\(profile.name)' → \(apiProfile.uuid)")
                }
            }
        }
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

        // Re-check CLI keychain for any credential changes during sleep
        detectCLIAccountChange()
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
        guard autoSwitchEnabled,
              let activeID = cliActiveProfileID,
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
        stopCLIMonitoring()
        for coordinator in coordinators.values {
            coordinator.stopPolling()
        }
    }
}
