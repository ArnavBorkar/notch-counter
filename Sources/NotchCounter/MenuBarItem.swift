import AppKit

/// A normal menu bar item, so there's an obvious way to open the board, restart,
/// or quit without hunting for the notch.
@MainActor
final class MenuBarItem: NSObject, NSMenuDelegate {
    private let app: AppState
    private let statusItem: NSStatusItem
    private let openBoard: () -> Void

    init(app: AppState, openBoard: @escaping () -> Void) {
        self.app = app
        self.openBoard = openBoard
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.icon()
            button.toolTip = "Notch Counter"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private static func icon() -> NSImage? {
        let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                            accessibilityDescription: "Notch Counter")
            ?? NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Notch Counter")
        image?.isTemplate = true
        return image
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if case .board = app.phase {
            menu.addItem(item("Open board", #selector(showBoard)))
            let status = NSMenuItem(
                title: "Day \(app.daysSinceStart)  ·  \(app.myCount) reached out  ·  \(app.tasksLeft) tasks left",
                action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(item("Refresh now", #selector(refresh)))
        } else {
            let status = NSMenuItem(title: label(for: app.phase), action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(item("Open panel", #selector(showBoard)))
        }

        if let release = app.update {
            menu.addItem(.separator())
            let update = item(app.installingUpdate
                              ? "Downloading \(release.version)…"
                              : "Install version \(release.version)…", #selector(installUpdate))
            update.isEnabled = !app.installingUpdate
            menu.addItem(update)
        }

        menu.addItem(.separator())

        let nudge = item("Nudge me every 8 minutes", #selector(flipNudges))
        nudge.state = app.nudgesEnabled ? .on : .off
        menu.addItem(nudge)

        let haptics = item("Trackpad haptics", #selector(flipHaptics))
        haptics.state = Haptics.enabled ? .on : .off
        menu.addItem(haptics)

        menu.addItem(.separator())

        if app.me != nil {
            menu.addItem(item("Log out", #selector(logOut)))
        }
        menu.addItem(item("Check for updates", #selector(checkUpdates)))
        menu.addItem(item("Change database…", #selector(changeDatabase)))
        menu.addItem(item("Restart", #selector(restart)))

        let quit = item("Quit Notch Counter", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func label(for phase: AppState.Phase) -> String {
        switch phase {
        case .setup:            return "No database configured"
        case .connecting:       return "Connecting…"
        case .failed:           return "Can't reach the database"
        case .login:            return "Not logged in"
        case .board:            return ""
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func showBoard() { openBoard() }

    @objc private func refresh() { Task { await app.refresh() } }

    @objc private func flipNudges() { app.toggleNudges() }

    @objc private func flipHaptics() {
        Haptics.setEnabled(!Haptics.enabled)
        if Haptics.enabled { Haptics.success() }
    }

    @objc private func logOut() { app.logOut() }

    @objc private func installUpdate() { app.installUpdate() }

    @objc private func checkUpdates() { Task { await app.checkForUpdate() } }

    @objc private func changeDatabase() { app.forgetDatabase() }

    /// Wait for this process to die, then launch a fresh one — otherwise `open`
    /// just re-activates the instance that's on its way out.
    @objc private func restart() {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return quit() }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c",
            "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; open \"\(bundle.path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
