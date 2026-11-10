import XCTest
import PDFKit
@testable import Inkdown

// Checks that a PDF is cut into one small PDF per page.
final class PDFSplitterTests: XCTestCase {

    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func testSplitsThreePagesIntoThreeOnePagePDFs() throws {
        let url = folder.appendingPathComponent("three.pdf")
        XCTAssertTrue(TestPDF.make(pages: 3).write(to: url))

        let pages = try PDFSplitter.pages(of: url)

        XCTAssertEqual(pages.count, 3)
        for data in pages {
            XCTAssertEqual(PDFDocument(data: data)?.pageCount, 1)
        }
    }

    func testPageCount() throws {
        let url = folder.appendingPathComponent("five.pdf")
        XCTAssertTrue(TestPDF.make(pages: 5).write(to: url))
        XCTAssertEqual(try PDFSplitter.pageCount(of: url), 5)
        XCTAssertThrowsError(try PDFSplitter.pageCount(of: folder.appendingPathComponent("no.pdf")))
    }

    func testMissingFileCannotBeOpened() {
        let url = folder.appendingPathComponent("nothing.pdf")
        XCTAssertThrowsError(try PDFSplitter.pages(of: url)) { error in
            XCTAssertEqual(error as? ConversionError, .cannotOpen)
        }
    }

    func testTextFileNamedPDFCannotBeOpened() throws {
        let url = folder.appendingPathComponent("fake.pdf")
        try "just text".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try PDFSplitter.pages(of: url)) { error in
            XCTAssertEqual(error as? ConversionError, .cannotOpen)
        }
    }
}

// Makes small PDFs for tests.
enum TestPDF {

    // A PDF with the given number of pages, each a plain grey rectangle.
    static func make(pages: Int) -> PDFDocument {
        let document = PDFDocument()
        for index in 0..<pages {
            let image = NSImage(size: NSSize(width: 200, height: 280))
            image.lockFocus()
            NSColor.lightGray.setFill()
            NSRect(x: 0, y: 0, width: 200, height: 280).fill()
            image.unlockFocus()
            if let page = PDFPage(image: image) {
                document.insert(page, at: index)
            }
        }
        return document
    }
}
