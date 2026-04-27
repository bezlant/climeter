import XCTest
@testable import Climeter

final class ProfileStoreStorageTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "fileBasedCredentialStorage")
        super.tearDown()
    }

    func test_fileBasedStorageDefaultsToFalse() {
        UserDefaults.standard.removeObject(forKey: "fileBasedCredentialStorage")

        XCTAssertFalse(ProfileStore.loadFileBasedStorage())
    }

    func test_saveFileBasedStorageRoundTrips() {
        ProfileStore.saveFileBasedStorage(true)
        XCTAssertTrue(ProfileStore.loadFileBasedStorage())

        ProfileStore.saveFileBasedStorage(false)
        XCTAssertFalse(ProfileStore.loadFileBasedStorage())
    }
}
