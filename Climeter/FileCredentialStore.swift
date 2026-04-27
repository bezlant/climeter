import Foundation

enum FileCredentialStore {
    static func credentialsURL(
        appSupportDir: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
    ) -> URL {
        appSupportDir
            .appendingPathComponent("Climeter")
            .appendingPathComponent("credentials.json")
    }

    static func save(
        _ jsonString: String,
        for profileID: UUID,
        appSupportDir: URL? = nil
    ) throws {
        let url = credentialsURL(appSupportDir: appSupportDir ?? defaultAppSupport())
        var store = loadStore(from: url)

        guard let data = jsonString.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else {
            return
        }
        store[profileID.uuidString] = obj
        try writeStore(store, to: url)
        Log.fileStore.info("save(\(profileID)): success")
    }

    static func read(
        for profileID: UUID,
        appSupportDir: URL? = nil
    ) -> String? {
        let url = credentialsURL(appSupportDir: appSupportDir ?? defaultAppSupport())
        let store = loadStore(from: url)
        guard let obj = store[profileID.uuidString] else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return nil }
        Log.fileStore.info("read(\(profileID)): success")
        return str
    }

    static func delete(
        for profileID: UUID,
        appSupportDir: URL? = nil
    ) throws {
        let url = credentialsURL(appSupportDir: appSupportDir ?? defaultAppSupport())
        var store = loadStore(from: url)
        store.removeValue(forKey: profileID.uuidString)
        try writeStore(store, to: url)
        Log.fileStore.info("delete(\(profileID)): success")
    }

    static func deleteAll(appSupportDir: URL? = nil) {
        let url = credentialsURL(appSupportDir: appSupportDir ?? defaultAppSupport())
        try? FileManager.default.removeItem(at: url)
        Log.fileStore.info("deleteAll: removed \(url.path)")
    }

    private static func defaultAppSupport() -> URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
    }

    private static func loadStore(from url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private static func writeStore(_ store: [String: Any], to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: store,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
