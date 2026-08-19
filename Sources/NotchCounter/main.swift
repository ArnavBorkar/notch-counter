import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private let counter = Counter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = NotchWindowController(counter: counter)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    // keep the delegate alive for the lifetime of the process
    withExtendedLifetime(delegate) { app.run() }
}
