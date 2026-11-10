import AppKit

// This is where the app starts.
// We create the app, give it our AppDelegate (the object that reacts to
// app events like "finished launching"), and start the event loop.
//
// MainActor.assumeIsolated tells Swift that this code runs on the main
// thread, which is where all user interface code has to run.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
