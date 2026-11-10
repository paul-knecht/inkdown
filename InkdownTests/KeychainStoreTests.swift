import XCTest
@testable import Inkdown

// Checks saving, reading and deleting a value in the macOS Keychain.
// Uses its own entry name so it never touches the real API key.
final class KeychainStoreTests: XCTestCase {

    private let store = KeychainStore(service: "local.inkdown.tests")

    override func tearDown() {
        store.delete()
    }

    func testSaveLoadDelete() {
        store.delete()
        XCTAssertNil(store.load())

        XCTAssertTrue(store.save("test-value"))
        XCTAssertEqual(store.load(), "test-value")

        XCTAssertTrue(store.save("second"))
        XCTAssertEqual(store.load(), "second")

        store.delete()
        XCTAssertNil(store.load())
    }
}
