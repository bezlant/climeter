import Foundation

enum ProfileStore {
    private static let profilesKey = "profiles"
    private static let activeProfileIDKey = "activeProfileID"
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
            // Silent failure for now - in production would log/handle error
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

    static func saveCredential(_ sessionKey: String, for profileID: UUID) throws {
        try KeychainService.save(sessionKey, for: profileID)
    }

    static func loadCredential(for profileID: UUID) throws -> String? {
        try KeychainService.read(for: profileID)
    }

    static func deleteCredential(for profileID: UUID) throws {
        try KeychainService.delete(for: profileID)
    }
}
