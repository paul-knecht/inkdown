import Foundation

// Decides where the Markdown file goes and what it is called.
enum OutputNaming {

    // notes.pdf → notes.md, in the same folder.
    static func defaultURL(for pdf: URL) -> URL {
        pdf.deletingPathExtension().appendingPathExtension("md")
    }

    // For "Keep Both": notes 2.md, or notes 3.md if that exists too, and so on.
    // `exists` answers whether a file is already there.
    static func keepBothURL(for pdf: URL, exists: (URL) -> Bool) -> URL {
        let folder = pdf.deletingLastPathComponent()
        let name = pdf.deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let candidate = folder.appendingPathComponent("\(name) \(number).md")
            if !exists(candidate) { return candidate }
            number += 1
        }
    }
}
