import AppKit

// Makes sure only one copy of Inkdown runs.
//
// There can be several copies of the app on disk (the installed one and the
// ones Xcode builds). If two run at once, there are two icons in the menu
// bar and a PDF could be converted twice. So a newly started copy asks all
// older copies to quit: the newest one wins.
enum SingleInstance {

    // The process numbers of the copies that should quit.
    // During automated tests nobody is asked to quit, because the tests
    // start their own copy next to the installed one.
    static func copiesToQuit(running: [pid_t], own: pid_t, isRunningTests: Bool) -> [pid_t] {
        if isRunningTests { return [] }
        return running.filter { $0 != own }
    }

    // Asks every other running copy of this app to quit.
    static func quitOlderCopies() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let copies = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let toQuit = copiesToQuit(running: copies.map(\.processIdentifier),
                                  own: ProcessInfo.processInfo.processIdentifier,
                                  isRunningTests: isRunningTests)
        for copy in copies where toQuit.contains(copy.processIdentifier) {
            copy.terminate()
        }
    }
}
