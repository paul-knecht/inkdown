import AppKit

// Lets the menu bar icon accept files that are dragged onto it.
//
// The icon lives in a tiny window of its own. We tell that window to accept
// dragged files and make this object its delegate; macOS then asks the
// delegate what to do when something is dragged over the icon.
final class DropTarget: NSObject, NSWindowDelegate, NSDraggingDestination {

    // Called with the dropped files.
    private let onDrop: ([URL]) -> Void

    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
    }

    // Starts accepting files dropped on the given menu bar icon.
    func attach(to statusItem: NSStatusItem) {
        guard let window = statusItem.button?.window else { return }
        window.registerForDraggedTypes([.fileURL])
        window.delegate = self
    }

    // The file addresses in the thing being dragged.
    private func urls(from info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    // Something is dragged over the icon: show the "copy" cursor if there is a PDF in it.
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        AppDelegate.pdfURLs(from: urls(from: sender)).isEmpty ? [] : .copy
    }

    // The files were dropped.
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pdfs = AppDelegate.pdfURLs(from: urls(from: sender))
        guard !pdfs.isEmpty else { return false }
        // Finish the drag first, then start; otherwise a question the app
        // asks would freeze Finder's drag animation.
        DispatchQueue.main.async { self.onDrop(pdfs) }
        return true
    }
}
