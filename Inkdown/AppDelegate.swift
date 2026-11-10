import AppKit
import UniformTypeIdentifiers

// The object that reacts to app events. It owns the menu bar icon and its
// menu, and it is where every way of starting a conversion arrives:
// Finder's right-click entry, a drop on the icon, "Choose PDF…" and "Open With".
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // The icon in the menu bar. We keep a reference so it doesn't disappear.
    var statusItem: NSStatusItem!

    // The first line of the menu. It shows what Inkdown is doing.
    let statusLine = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")

    // The "Cancel" menu item. It is only visible while a PDF is converted.
    var cancelItem: NSMenuItem!

    // Where the API key is stored.
    let keychain = KeychainStore()

    // Converts the PDFs one after another.
    var queue: ConversionQueue!

    // Accepts PDFs dropped on the menu bar icon.
    var dropTarget: DropTarget!

    // Above this many pages Inkdown asks before it starts, because of the cost.
    static let askAbovePages = 50

    // Everything is set up here, before the app has finished launching.
    // When Inkdown is started by "Open With" or by the Finder entry, macOS
    // hands over the PDF very early, and the queue must exist by then.
    func applicationWillFinishLaunching(_ notification: Notification) {
        installEditMenu()
        installStatusItem()
        installQueue()

        // Tell macOS that this object answers the "Convert to Markdown"
        // entry in Finder's right-click menu (declared in Config/Info.plist).
        NSApp.servicesProvider = self

        dropTarget = DropTarget { [weak self] urls in self?.convert(urls: urls) }
        dropTarget.attach(to: statusItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy of Inkdown may run; this one replaces any older copy.
        SingleInstance.quitOlderCopies()
    }

    // MARK: Setup

    // Gives the app an Edit menu. It is never visible (Inkdown has no menu
    // bar of its own), but macOS uses it to make ⌘X, ⌘C, ⌘V and ⌘A work in
    // text fields, for example when pasting the API key.
    private func installEditMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    // Creates the menu bar icon and the menu that opens when it is clicked.
    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "doc.text",
                                           accessibilityDescription: "Inkdown")
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(item("Choose PDF…", #selector(choosePDF)))
        cancelItem = item("Cancel", #selector(cancelConversion))
        cancelItem.isHidden = true
        menu.addItem(cancelItem)
        menu.addItem(item("Set API key…", #selector(setAPIKey)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // Makes a menu item that calls one of our own functions.
    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // Creates the queue and connects it to the real PDF splitter, Claude
    // and the file system.
    private func installQueue() {
        let keychain = self.keychain
        queue = ConversionQueue(
            split: { url in try PDFSplitter.pages(of: url) },
            makeConverter: {
                // The key is read once per PDF, when its conversion starts.
                let key = keychain.load()
                return Converter(transcribe: { data, page, total in
                    try await ClaudeClient.transcribe(pagePDF: data, page: page, of: total, apiKey: key)
                })
            },
            write: { [weak self] text, url in
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    return url
                } catch {
                    // Saving next to the PDF failed (a read-only folder, for
                    // example). The pages are already paid for, so let the
                    // user pick another place instead of losing the text.
                    guard let other = self?.askWhereToSave(insteadOf: url) else { throw error }
                    try text.write(to: other, atomically: true, encoding: .utf8)
                    return other
                }
            })
        queue.onStatus = { [weak self] status in self?.show(status) }
        queue.onOutcome = { [weak self] outcome in self?.handle(outcome) }
    }

    // MARK: Showing what is going on

    // Updates the menu's first line, the text next to the icon and "Cancel".
    func show(_ status: QueueStatus) {
        statusLine.title = status.menuTitle
        statusItem.button?.title = status.iconTitle
        cancelItem.isHidden = !queue.isBusy
    }

    // Called when a PDF is finished or has failed.
    func handle(_ outcome: JobOutcome) {
        switch outcome {
        case .done(let output, let result):
            // Show the new file in Finder.
            NSWorkspace.shared.activateFileViewerSelecting([output])
            if let message = AppDelegate.problemMessage(unreadable: result.unreadablePages,
                                                        cutOff: result.incompletePages) {
                showMessageLater(title: "“\(output.lastPathComponent)” has gaps", text: message)
            }
        case .failed(let pdf, let error):
            showMessageLater(title: "“\(pdf.lastPathComponent)” was not converted", text: error.message)
        }
    }

    // Shows a message a moment later instead of right now. A message
    // waits for a click on OK; shown right away, it would hold up the
    // queue, and the next PDF would not start until someone clicked.
    private func showMessageLater(title: String, text: String) {
        DispatchQueue.main.async { self.showMessage(title: title, text: text) }
    }

    // The sentences that name unreadable and cut-off pages, or nil if all went well.
    nonisolated static func problemMessage(unreadable: [Int], cutOff: [Int]) -> String? {
        func subject(_ pages: [Int]) -> String {
            let list = pages.map(String.init).joined(separator: ", ")
            return pages.count == 1 ? "Page \(list)" : "Pages \(list)"
        }
        var sentences: [String] = []
        if !unreadable.isEmpty {
            sentences.append("\(subject(unreadable)) could not be read. The file marks each place with [PAGE … COULD NOT BE READ].")
        }
        if !cutOff.isEmpty {
            sentences.append("\(subject(cutOff)) had too much text for one answer and stopped early. The file marks each place with [PAGE … WAS CUT OFF].")
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    // Lets the user choose where to save a Markdown file. Returns nil on Cancel.
    private func askWhereToSave(insteadOf url: URL) -> URL? {
        let panel = NSSavePanel()
        panel.message = "“\(url.lastPathComponent)” could not be saved next to the PDF. Choose another place."
        panel.nameFieldStringValue = url.lastPathComponent
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    // Shows a message with an OK button.
    private func showMessage(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // Asks a question. Returns the number of the chosen button, starting at 0.
    private func ask(title: String, text: String, buttons: [String]) -> Int {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        for button in buttons { alert.addButton(withTitle: button) }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    // MARK: The ways a conversion starts

    // Keeps only the PDF files from a list of files.
    nonisolated static func pdfURLs(from urls: [URL]) -> [URL] {
        urls.filter { $0.isFileURL && $0.pathExtension.lowercased() == "pdf" && !$0.hasDirectoryPath }
    }

    // Finder's right-click entry "Convert to Markdown" arrives here.
    // macOS hands over the selected files on a pasteboard.
    @objc func convertToMarkdown(_ pboard: NSPasteboard, userData: String,
                                 error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        // Answer macOS first, then start; a question we ask must not keep Finder waiting.
        DispatchQueue.main.async { self.convert(urls: urls) }
    }

    // "Open With › Inkdown" and files dropped on the app's icon arrive here.
    func application(_ application: NSApplication, open urls: [URL]) {
        convert(urls: urls)
    }

    // Lets the user pick PDF files in a standard file dialog.
    @objc func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose the PDFs to convert to Markdown"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        convert(urls: panel.urls)
    }

    @objc func cancelConversion() {
        queue.cancelAll()
    }

    // Every way of starting ends up here. Checks each PDF, asks what needs
    // asking, and puts it in the queue. Nothing is sent before that.
    func convert(urls: [URL]) {
        let pdfs = AppDelegate.pdfURLs(from: urls)
        guard !pdfs.isEmpty else { return }

        // 1. Without an API key nothing can be converted.
        if (keychain.load() ?? "").isEmpty {
            let choice = ask(title: "Inkdown needs an Anthropic API key",
                             text: "Claude reads the pages of your PDF. For that, Inkdown needs your Anthropic API key.",
                             buttons: ["Set API key…", "Cancel"])
            guard choice == 0 else { return }
            setAPIKey()
            guard !(keychain.load() ?? "").isEmpty else { return }
        }

        for pdf in pdfs {
            // A PDF that is already being converted or waiting is not added twice.
            if queue.isQueued(pdf) { continue }

            // 2. Can the PDF be read at all?
            let pageCount: Int
            do {
                pageCount = try PDFSplitter.pageCount(of: pdf)
            } catch {
                let reason = (error as? ConversionError)?.message ?? ConversionError.cannotOpen.message
                showMessage(title: "“\(pdf.lastPathComponent)” was not converted", text: reason)
                continue
            }

            // 3. Never overwrite an existing file without asking.
            var output = OutputNaming.defaultURL(for: pdf)
            if FileManager.default.fileExists(atPath: output.path) {
                let choice = ask(title: "“\(output.lastPathComponent)” already exists",
                                 text: "Do you want to replace it, or keep it and save the new file under another name?",
                                 buttons: ["Keep Both", "Replace", "Cancel"])
                if choice == 2 { continue }
                if choice == 0 {
                    // Skip names that exist and names another waiting PDF will use.
                    let reserved = queue.reservedOutputs.map(\.path)
                    output = OutputNaming.keepBothURL(for: pdf) {
                        FileManager.default.fileExists(atPath: $0.path) || reserved.contains($0.path)
                    }
                }
            }

            // If the PDF's folder cannot be written to, ask for another
            // place now, before any page is sent and paid for.
            let folder = output.deletingLastPathComponent().path
            if !FileManager.default.isWritableFile(atPath: folder) {
                guard let other = askWhereToSave(insteadOf: output) else { continue }
                output = other
            }

            // 4. Long PDFs cost more; ask once.
            if pageCount > AppDelegate.askAbovePages {
                let choice = ask(title: "“\(pdf.lastPathComponent)” has \(pageCount) pages",
                                 text: AppDelegate.costQuestion(pages: pageCount),
                                 buttons: ["Convert", "Cancel"])
                if choice != 0 { continue }
            }

            queue.add(Job(pdf: pdf, output: output))
        }
    }

    // The question shown before a long PDF, with a rough cost of 2 to 4 cents per page.
    nonisolated static func costQuestion(pages: Int) -> String {
        let low = String(format: "%.2f", Double(pages) * 0.02)
        let high = String(format: "%.2f", Double(pages) * 0.04)
        return "Converting it will cost roughly $\(low) to $\(high). Do you want to continue?"
    }

    // MARK: API key

    // Shows a small dialog where the user types their Anthropic API key.
    // The field hides what is typed, and the key goes straight into the Keychain.
    @objc func setAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Anthropic API key"
        alert.informativeText = "The key is stored in your Mac's Keychain. Leave the field empty and press Save to remove a stored key."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        // A menu-bar-only app has to step forward, or the dialog opens behind other windows.
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            keychain.delete()
        } else if !keychain.save(key) {
            showMessage(title: "The key could not be stored",
                        text: "The Keychain did not accept the key. Try Set API key… again.")
        }
    }
}
