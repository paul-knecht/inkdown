import AppKit

// The object that reacts to app events. It owns the menu bar icon and its
// menu, and it is where every way of starting a conversion arrives.
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // The icon in the menu bar. We keep a reference so it doesn't disappear.
    var statusItem: NSStatusItem!

    // The first line of the menu. It shows what Inkdown is doing.
    let statusLine = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")

    // Where the API key is stored.
    let keychain = KeychainStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only one copy of Inkdown may run; this one replaces any older copy.
        SingleInstance.quitOlderCopies()

        installEditMenu()
        installStatusItem()
    }

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

    // Lets the user pick PDF files in a standard file dialog.
    @objc func choosePDF() {
    }

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
        } else {
            keychain.save(key)
        }
    }
}
