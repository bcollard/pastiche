import AppKit

// Hand-rolled entry point rather than `@main`: the app is an accessory
// (no Dock icon, no main window) and needs its activation policy set before
// anything else touches the shared application.
//
// Top-level code is not main-actor isolated, but it does run on the main
// thread here, so the setup is wrapped rather than hopped.
let application = NSApplication.shared

let delegate: AppDelegate = MainActor.assumeIsolated {
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    return delegate
}

application.run()
