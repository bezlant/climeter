import XCTest
@testable import Climeter

final class CLISyncFileReadTests: XCTestCase {
    private var tempHome: URL!

    override func setUp() {
        super.setUp()
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempHome)
        super.tearDown()
    }

    func test_readFromHiddenCredentialsFile() throws {
        let claudeDir = tempHome.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let json = """
        {"claudeAiOauth":{"accessToken":"file-at","refreshToken":"file-rt","expiresAt":1700000000000}}
        """
        try json.write(
            to: claudeDir.appendingPathComponent(".credentials.json"),
            atomically: true,
            encoding: .utf8
        )

        let cred = ClaudeCodeSyncService.readCLICredentialFromFile(homeDirectory: tempHome)
        XCTAssertNotNil(cred)
        XCTAssertEqual(cred?.accessToken, "file-at")
        XCTAssertEqual(cred?.refreshToken, "file-rt")
    }

    func test_readFromNonHiddenCredentialsFile() throws {
        let claudeDir = tempHome.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let json = """
        {"claudeAiOauth":{"accessToken":"file-at2","refreshToken":"file-rt2","expiresAt":1700000000000}}
        """
        try json.write(
            to: claudeDir.appendingPathComponent("credentials.json"),
            atomically: true,
            encoding: .utf8
        )

        let cred = ClaudeCodeSyncService.readCLICredentialFromFile(homeDirectory: tempHome)
        XCTAssertNotNil(cred)
        XCTAssertEqual(cred?.accessToken, "file-at2")
    }

    func test_hiddenFilePreferredOverNonHidden() throws {
        let claudeDir = tempHome.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        let hidden = """
        {"claudeAiOauth":{"accessToken":"hidden","refreshToken":"r","expiresAt":1000}}
        """
        let visible = """
        {"claudeAiOauth":{"accessToken":"visible","refreshToken":"r","expiresAt":1000}}
        """
        try hidden.write(
            to: claudeDir.appendingPathComponent(".credentials.json"),
            atomically: true,
            encoding: .utf8
        )
        try visible.write(
            to: claudeDir.appendingPathComponent("credentials.json"),
            atomically: true,
            encoding: .utf8
        )

        let cred = ClaudeCodeSyncService.readCLICredentialFromFile(homeDirectory: tempHome)
        XCTAssertEqual(cred?.accessToken, "hidden")
    }

    func test_returnsNilWhenNoFileExists() {
        let cred = ClaudeCodeSyncService.readCLICredentialFromFile(homeDirectory: tempHome)
        XCTAssertNil(cred)
    }

    func test_returnsNilWhenFileIsUnparseable() throws {
        let claudeDir = tempHome.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

        try "not json".write(
            to: claudeDir.appendingPathComponent(".credentials.json"),
            atomically: true,
            encoding: .utf8
        )

        let cred = ClaudeCodeSyncService.readCLICredentialFromFile(homeDirectory: tempHome)
        XCTAssertNil(cred)
    }
}
