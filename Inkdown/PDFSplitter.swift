import Foundation
import PDFKit

// Cuts a PDF into one small PDF per page.
//
// Each page is sent to Claude on its own. That way no page can be skipped
// or shortened, and a page that fails can be tried again alone.
enum PDFSplitter {

    // Opens the PDF and checks that it can be read. Throws if not.
    private static func open(_ url: URL) throws -> PDFDocument {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.cannotOpen
        }
        // Some PDFs are "encrypted" with an empty password; try that first.
        if document.isLocked && !document.unlock(withPassword: "") {
            throw ConversionError.locked
        }
        guard document.pageCount > 0 else {
            throw ConversionError.empty
        }
        return document
    }

    // How many pages the PDF has. Used to check a file before converting it.
    static func pageCount(of url: URL) throws -> Int {
        try open(url).pageCount
    }

    // Returns one single-page PDF (as raw data) for every page of the file.
    static func pages(of url: URL) throws -> [Data] {
        let document = try open(url)

        var pages: [Data] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index),
                  let copy = page.copy() as? PDFPage else {
                throw ConversionError.cannotOpen
            }
            let single = PDFDocument()
            single.insert(copy, at: 0)
            guard let data = single.dataRepresentation() else {
                throw ConversionError.cannotOpen
            }
            pages.append(data)
        }
        return pages
    }
}
