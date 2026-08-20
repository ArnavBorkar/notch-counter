import AppKit
import SwiftUI

/// Hosts the SwiftUI view but only accepts clicks that land on the visible notch shape,
/// so the rest of the menu bar keeps working.
final class PassthroughContainer: NSView {
    var activeRect: NSRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard activeRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    var nudgesEnabled: () -> Bool = { true }
    var toggleNudges: () -> Void = {}

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let nudge = NSMenuItem(title: "Nudge me every minute",
                               action: #selector(flipNudges), keyEquivalent: "")
        nudge.target = self
        nudge.state = nudgesEnabled() ? .on : .off
        menu.addItem(nudge)

        let haptics = NSMenuItem(title: "Trackpad haptics", action: #selector(flipHaptics), keyEquivalent: "")
        haptics.target = self
        haptics.state = Haptics.enabled ? .on : .off
        menu.addItem(haptics)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notch Counter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func flipNudges() { toggleNudges() }

    @objc private func flipHaptics() {
        MainActor.assumeIsolated {
            Haptics.setEnabled(!Haptics.enabled)
            if Haptics.enabled { Haptics.success() }
        }
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchWindowController {
    private let app: AppState
    private var geo: NotchGeometry
    private var panel: NotchPanel!
    private var container: PassthroughContainer!
    private var pollTimer: Timer?
    private var monitors: [Any] = []

    /// Hover hysteresis — a full-size board shouldn't fly open on a stray pointer.
    private var insideSince: Date?
    private var outsideSince: Date?
    private let openDelay: TimeInterval = 0.18
    private let closeDelay: TimeInterval = 0.35

    init(app: AppState) {
        self.app = app
        self.geo = NotchGeometry.current()
        build()
        startTracking()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }
    }

    private func build() {
        let panel = NotchPanel(contentRect: geo.windowFrame,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered,
                               defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let container = PassthroughContainer(frame: NSRect(origin: .zero, size: geo.windowSize))
        let hosting = NSHostingView(rootView: NotchView(app: app, geo: geo))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        container.nudgesEnabled = { [weak app] in app?.nudgesEnabled ?? true }
        container.toggleNudges = { [weak app] in app?.toggleNudges() }
        panel.contentView = container
        panel.setFrame(geo.windowFrame, display: true)
        panel.orderFrontRegardless()

        self.panel = panel
        self.container = container
        updateActiveRect()
    }

    private func relayout() {
        geo = NotchGeometry.current()
        panel.setFrame(geo.windowFrame, display: true)
        container.frame = NSRect(origin: .zero, size: geo.windowSize)
        if let hosting = container.subviews.first as? NSHostingView<NotchView> {
            hosting.rootView = NotchView(app: app, geo: geo)
            hosting.frame = container.bounds
        }
        updateActiveRect()
    }

    /// Clickable region, in container coordinates.
    private func updateActiveRect() {
        let expanded = app.expanded
        let size = expanded ? geo.openSize(app.panelMode) : geo.closedSize
        container.activeRect = NSRect(x: geo.leadingOffset(open: expanded, mode: app.panelMode),
                                      y: geo.windowSize.height - size.height,
                                      width: size.width,
                                      height: size.height)
    }

    private func currentShapeOnScreen() -> NSRect {
        geo.shapeRectOnScreen(open: app.expanded, mode: app.panelMode)
    }

    // MARK: - Tracking

    private func startTracking() {
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        // Click inside pins the panel open (so it survives you reaching for the keyboard);
        // click anywhere else lets it go.
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleClickOutside() }
        }
        if let globalMonitor { monitors.append(globalMonitor) }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.pin() }
            return event
        }
        if let localMonitor { monitors.append(localMonitor) }

        let keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }   // esc
            MainActor.assumeIsolated { self.unpin(closing: true) }
            return nil
        }
        if let keyMonitor { monitors.append(keyMonitor) }
    }

    private func pin() {
        guard app.expanded, !app.pinned else { return }
        app.pinned = true
        panel.makeKeyAndOrderFront(nil)
        updateActiveRect()
    }

    private func handleClickOutside() {
        guard app.pinned else { return }
        let mouse = NSEvent.mouseLocation
        guard !currentShapeOnScreen().contains(mouse) else { return }
        unpin(closing: true)
    }

    private func unpin(closing: Bool) {
        guard app.pinned || closing else { return }
        app.pinned = false
        app.confirmingReset = false
        if closing, !currentShapeOnScreen().contains(NSEvent.mouseLocation) {
            app.isOpen = false
        }
        NSApp.deactivate()
        updateActiveRect()
    }

    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        let rect = app.expanded
            ? currentShapeOnScreen().insetBy(dx: -12, dy: -12)   // grace so it doesn't snap shut at the edges
            : geo.shapeRectOnScreen(open: false, mode: app.panelMode)
        let inside = rect.contains(mouse)
        let now = Date()

        if inside {
            outsideSince = nil
            if insideSince == nil { insideSince = now }
            if !app.isOpen, now.timeIntervalSince(insideSince ?? now) >= openDelay {
                app.isOpen = true
                Haptics.expand()
                app.panelDidOpen()
                updateActiveRect()
            }
        } else {
            insideSince = nil
            if app.pinned { return }
            if outsideSince == nil { outsideSince = now }
            if app.isOpen, now.timeIntervalSince(outsideSince ?? now) >= closeDelay {
                app.isOpen = false
                Haptics.collapse()
                app.confirmingReset = false
                updateActiveRect()
            }
        }
    }
}
