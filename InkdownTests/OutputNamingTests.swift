import XCTest
@testable import Inkdown

// Checks where the Markdown file goes and what it is called.
final class OutputNamingTests: XCTestCase {

    private let pdf = URL(fileURLWithPath: "/tmp/notes/notes.pdf")

    func testDefaultNameSitsNextToThePDF() {
        XCTAssertEqual(OutputNaming.defaultURL(for: pdf).path, "/tmp/notes/notes.md")
    }

    func testNameWithDotsKeepsEverythingButTheEnding() {
        let dotted = URL(fileURLWithPath: "/tmp/a.b.pdf")
        XCTAssertEqual(OutputNaming.defaultURL(for: dotted).path, "/tmp/a.b.md")
    }

    func testKeepBothUsesTheFirstFreeNumber() {
        let taken: Set<String> = ["/tmp/notes/notes.md", "/tmp/notes/notes 2.md"]
        let url = OutputNaming.keepBothURL(for: pdf) { taken.contains($0.path) }
        XCTAssertEqual(url.path, "/tmp/notes/notes 3.md")
    }

    func testKeepBothStartsAtTwo() {
        let url = OutputNaming.keepBothURL(for: pdf) { _ in false }
        XCTAssertEqual(url.path, "/tmp/notes/notes 2.md")
    }
}
