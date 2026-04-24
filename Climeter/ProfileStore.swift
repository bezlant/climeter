import Foundation

enum ProfileStore {
    private static let profilesKey = "profiles"
    private static let activeProfileIDKey = "activeProfileID"
    private static let cliActiveProfileIDKey = "cliActiveProfileID"
    private static let autoSwitchEnabledKey = "autoSwitchEnabled"
    private static let autoSwitchThresholdKey = "autoSwitchThreshold"
    private static let codexEnabledKey = "codexEnabled"
    private static let defaults = UserDefaults.standard

    static func loadProfiles() -> [Profile] {
        guard let data = defaults.data(forKey: profilesKey) else {
            return []
        }

        do {
            let profiles = try JSONDecoder().decode([Profile].self, from: data)
            return profiles
        } catch {
            return []
        }
    }

    static func saveProfiles(_ profiles: [Profile]) {
        do {
            let data = try JSONEncoder().encode(profiles)
            defaults.set(data, forKey: profilesKey)
        } catch {
            // Silent failure
        }
    }

    static func loadActiveProfileID() -> UUID? {
        guard let uuidString = defaults.string(forKey: activeProfileIDKey) else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }

    static func saveActiveProfileID(_ id: UUID) {
        defaults.set(id.uuidString, forKey: activeProfileIDKey)
    }

    static func loadCLIActiveProfileID() -> UUID? {
        guard let uuidString = defaults.string(forKey: cliActiveProfileIDKey) else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }

    static func saveCLIActiveProfileID(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: cliActiveProfileIDKey)
        } else {
            defaults.removeObject(forKey: cliActiveProfileIDKey)
        }
    }

    // MARK: - Auto-Switch Settings

    static func loadAutoSwitchEnabled() -> Bool {
        // Default to off if never set
        if defaults.object(forKey: autoSwitchEnabledKey) == nil { return false }
        return defaults.bool(forKey: autoSwitchEnabledKey)
    }

    static func saveAutoSwitchEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: autoSwitchEnabledKey)
    }

    static func loadAutoSwitchThreshold() -> Double {
        let value = defaults.double(forKey: autoSwitchThresholdKey)
        return value > 0 ? value : 95.0
    }

    static func saveAutoSwitchThreshold(_ threshold: Double) {
        defaults.set(threshold, forKey: autoSwitchThresholdKey)
    }

    // MARK: - Codex Settings

    static func loadCodexEnabled() -> Bool {
        defaults.object(forKey: codexEnabledKey) as? Bool ?? true
    }

    static func saveCodexEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: codexEnabledKey)
    }

    // Raw string credential operations (Keychain stores raw JSON)
    static func saveCredential(_ sessionKey: String, for profileID: UUID) throws {
        try KeychainService.save(sessionKey, for: profileID)
    }

    static func loadCredential(for profileID: UUID) throws -> String? {
        try KeychainService.read(for: profileID)
    }

    static func deleteCredential(for profileID: UUID) throws {
        try KeychainService.delete(for: profileID)
    }

    // Credential model convenience methods
    static func saveCredentialModel(_ credential: Credential, for profileID: UUID) throws {
        try saveCredential(credential.toJSONString(), for: profileID)
    }

    static func loadCredentialModel(for profileID: UUID) -> Credential? {
        guard let raw = try? loadCredential(for: profileID) else { return nil }
        return Credential(jsonString: raw)
    }
}
