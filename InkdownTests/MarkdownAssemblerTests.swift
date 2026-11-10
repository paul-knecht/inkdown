import XCTest
@testable import Inkdown

// Checks how the texts of single pages are joined into one Markdown file.
final class MarkdownAssemblerTests: XCTestCase {

    func testAssemblesPagesWithMarkers() {
        let markdown = MarkdownAssembler.assemble([.text("A"), .blank, .unreadable, .text("D")])
        XCTAssertEqual(markdown,
            "<!-- Page 1 -->\n\nA\n\n<!-- Page 3 -->\n\n[PAGE 3 COULD NOT BE READ]\n\n<!-- Page 4 -->\n\nD\n")
    }

    func testNothingToAssembleGivesEmptyText() {
        XCTAssertEqual(MarkdownAssembler.assemble([]), "")
        XCTAssertEqual(MarkdownAssembler.assemble([.blank, .blank]), "")
    }

    func testCleanRemovesAFenceAroundTheWholeText() {
        XCTAssertEqual(MarkdownAssembler.clean("```markdown\n# T\n```"), .text("# T"))
        XCTAssertEqual(MarkdownAssembler.clean("```\n# T\nmore\n```\n"), .text("# T\nmore"))
    }

    func testCleanKeepsFencesInsideTheText() {
        XCTAssertEqual(MarkdownAssembler.clean("a ``` b"), .text("a ``` b"))
        let withCode = "Intro\n```\ncode\n```"
        XCTAssertEqual(MarkdownAssembler.clean(withCode), .text(withCode))
    }

    func testOnlyTheExactMarkerMeansBlank() {
        XCTAssertEqual(MarkdownAssembler.clean("  [BLANK PAGE]\n"), .blank)
    }

    // An empty answer is a failure, not a blank page: the page must not
    // vanish from the file without a trace.
    func testAnEmptyAnswerIsUnreadableNotBlank() {
        XCTAssertEqual(MarkdownAssembler.clean(""), .unreadable)
        XCTAssertEqual(MarkdownAssembler.clean(" \n "), .unreadable)
        XCTAssertEqual(MarkdownAssembler.clean("```\n```"), .unreadable)
    }

    func testCleanTrimsSpaceAroundText() {
        XCTAssertEqual(MarkdownAssembler.clean("\n\nHello\n"), .text("Hello"))
    }
}
