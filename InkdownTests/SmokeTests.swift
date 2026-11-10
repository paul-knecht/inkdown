import XCTest
@testable import Inkdown

// Checks that the app starts with our AppDelegate in charge.
final class SmokeTests: XCTestCase {

    func testAppDelegateExists() {
        XCTAssertTrue(NSApp.delegate is AppDelegate)
    }

    // ⌘V, ⌘C, ⌘X and ⌘A only work in text fields (like the API key field)
    // if the app has an Edit menu that carries those shortcuts.
    func testEditShortcutsExistSoPasteWorks() throws {
        let menus = NSApp.mainMenu?.items.compactMap(\.submenu) ?? []
        let keys = menus.flatMap(\.items).map(\.keyEquivalent)
        for key in ["x", "c", "v", "a"] {
            XCTAssertTrue(keys.contains(key), "No menu item with ⌘\(key.uppercased())")
        }
    }
}
