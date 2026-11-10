import XCTest
@testable import Inkdown

// Checks the pieces behind the ways of starting a conversion.
final class EntranceTests: XCTestCase {

    func testOnlyPDFFilesAreKept() {
        let urls = [
            URL(fileURLWithPath: "/tmp/a.pdf"),
            URL(fileURLWithPath: "/tmp/B.PDF"),
            URL(fileURLWithPath: "/tmp/c.txt"),
            URL(fileURLWithPath: "/tmp/folder.pdf/", isDirectory: true),
            URL(string: "https://example.com/d.pdf")!,
        ]
        XCTAssertEqual(AppDelegate.pdfURLs(from: urls).map(\.lastPathComponent), ["a.pdf", "B.PDF"])
        XCTAssertEqual(AppDelegate.pdfURLs(from: []), [])
    }

    // The entry in Finder's right-click menu is declared in the app's Info.plist.
    func testTheAppDeclaresTheFinderService() throws {
        let services = try XCTUnwrap(Bundle.main.infoDictionary?["NSServices"] as? [[String: Any]])
        let service = try XCTUnwrap(services.first)
        XCTAssertEqual((service["NSMenuItem"] as? [String: Any])?["default"] as? String, "Convert to Markdown")
        XCTAssertEqual(service["NSMessage"] as? String, "convertToMarkdown")
        XCTAssertEqual(service["NSSendFileTypes"] as? [String], ["com.adobe.pdf"])
    }

    // macOS calls the service by this exact name; a typo would fail silently.
    @MainActor
    func testTheAppAnswersTheFinderService() throws {
        let delegate = try XCTUnwrap(NSApp.delegate as? AppDelegate)
        XCTAssertTrue(delegate.responds(to: Selector(("convertToMarkdown:userData:error:"))))
        XCTAssertTrue(NSApp.servicesProvider as AnyObject === delegate)
    }

    func testTheAppCanOpenPDFsButIsNeverTheDefault() throws {
        let types = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]])
        let pdf = try XCTUnwrap(types.first)
        XCTAssertEqual(pdf["LSItemContentTypes"] as? [String], ["com.adobe.pdf"])
        XCTAssertEqual(pdf["LSHandlerRank"] as? String, "Alternate")
    }

    func testTheAppStaysOutOfTheDock() {
        XCTAssertEqual(Bundle.main.infoDictionary?["LSUIElement"] as? Bool, true)
    }

    func testEveryErrorHasAMessage() {
        let claude: [ClaudeError] = [.noKey, .offline, .unauthorized, .noCredit, .busy, .refused, .tooLarge, .failed]
        for error in claude {
            XCTAssertFalse(error.message.isEmpty)
            XCTAssertEqual(ConversionError.stopped(error).message, error.message)
        }
        let conversion: [ConversionError] = [.cannotOpen, .locked, .empty, .cancelled, .cannotWrite]
        for error in conversion {
            XCTAssertFalse(error.message.isEmpty)
        }
    }

    func testUnreadablePagesAreNamed() {
        XCTAssertNil(AppDelegate.unreadableMessage(pages: []))
        XCTAssertTrue(AppDelegate.unreadableMessage(pages: [3])!.hasPrefix("Page 3 could not be read."))
        XCTAssertTrue(AppDelegate.unreadableMessage(pages: [2, 5])!.hasPrefix("Pages 2, 5 could not be read."))
    }

    func testCostQuestionForALongPDF() {
        XCTAssertEqual(AppDelegate.costQuestion(pages: 100),
                       "Converting it will cost roughly $2.00 to $4.00. Do you want to continue?")
    }
}
