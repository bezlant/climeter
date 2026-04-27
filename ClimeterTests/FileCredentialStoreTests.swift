import XCTest
@testable import Climeter

final class FileCredentialStoreTests: XCTestCase {
    private var tempDir: URL!
    private var credURL: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        credURL = tempDir
            .appendingPathComponent("Climeter")
            .appendingPathComponent("credentials.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func test_readReturnsNilWhenNoFileExists() {
        let result = FileCredentialStore.read(
            for: UUID(),
            appSupportDir: tempDir
        )
        XCTAssertNil(result)
    }

    func test_saveAndReadRoundTrip() throws {
        let profileID = UUID()
        let json = """
        {"claudeAiOauth":{"accessToken":"at","refreshToken":"rt","expiresAt":1700000000000}}
        """

        try FileCredentialStore.save(json, for: profileID, appSupportDir: tempDir)
        let loaded = FileCredentialStore.read(for: profileID, appSupportDir: tempDir)

        XCTAssertNotNil(loaded)
        let cred = Credential(jsonString: loaded!)
        XCTAssertNotNil(cred)
        XCTAssertEqual(cred?.accessToken, "at")
        XCTAssertEqual(cred?.refreshToken, "rt")
    }

    func test_multipleProfilesStoredInSameFile() throws {
        let id1 = UUID()
        let id2 = UUID()
        let json1 = """
        {"claudeAiOauth":{"accessToken":"a1","refreshToken":"r1","expiresAt":1000}}
        """
        let json2 = """
        {"claudeAiOauth":{"accessToken":"a2","refreshToken":"r2","expiresAt":2000}}
        """

        try FileCredentialStore.save(json1, for: id1, appSupportDir: tempDir)
        try FileCredentialStore.save(json2, for: id2, appSupportDir: tempDir)

        let loaded1 = FileCredentialStore.read(for: id1, appSupportDir: tempDir)
        let loaded2 = FileCredentialStore.read(for: id2, appSupportDir: tempDir)

        XCTAssertEqual(Credential(jsonString: loaded1!)?.accessToken, "a1")
        XCTAssertEqual(Credential(jsonString: loaded2!)?.accessToken, "a2")
    }

    func test_deleteRemovesOnlyTargetProfile() throws {
        let id1 = UUID()
        let id2 = UUID()
        let json = """
        {"claudeAiOauth":{"accessToken":"x","refreshToken":"y","expiresAt":1000}}
        """

        try FileCredentialStore.save(json, for: id1, appSupportDir: tempDir)
        try FileCredentialStore.save(json, for: id2, appSupportDir: tempDir)
        try FileCredentialStore.delete(for: id1, appSupportDir: tempDir)

        XCTAssertNil(FileCredentialStore.read(for: id1, appSupportDir: tempDir))
        XCTAssertNotNil(FileCredentialStore.read(for: id2, appSupportDir: tempDir))
    }

    func test_deleteAllRemovesFile() throws {
        let id = UUID()
        let json = """
        {"claudeAiOauth":{"accessToken":"x","refreshToken":"y","expiresAt":1000}}
        """
        try FileCredentialStore.save(json, for: id, appSupportDir: tempDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: credURL.path))

        FileCredentialStore.deleteAll(appSupportDir: tempDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: credURL.path))
    }

    func test_filePermissionsAreOwnerOnly() throws {
        let id = UUID()
        let json = """
        {"claudeAiOauth":{"accessToken":"x","refreshToken":"y","expiresAt":1000}}
        """
        try FileCredentialStore.save(json, for: id, appSupportDir: tempDir)

        let attrs = try FileManager.default.attributesOfItem(atPath: credURL.path)
        let perms = attrs[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func test_saveOverwritesExistingProfile() throws {
        let id = UUID()
        let json1 = """
        {"claudeAiOauth":{"accessToken":"old","refreshToken":"r","expiresAt":1000}}
        """
        let json2 = """
        {"claudeAiOauth":{"accessToken":"new","refreshToken":"r","expiresAt":2000}}
        """

        try FileCredentialStore.save(json1, for: id, appSupportDir: tempDir)
        try FileCredentialStore.save(json2, for: id, appSupportDir: tempDir)

        let loaded = FileCredentialStore.read(for: id, appSupportDir: tempDir)
        XCTAssertEqual(Credential(jsonString: loaded!)?.accessToken, "new")
    }
}
