import AppKit
import SwiftUI

/// Hosts the SwiftUI view but only accepts clicks that land on the visible notch shape,
/// so the rest of the menu bar keeps working normally.
final class PassthroughContainer: NSView {
    var activeRect: NSRect = .zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard activeRect.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Notch Counter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchWindowController {
    private let counter: Counter
    private var geo: NotchGeometry
    private var panel: NotchPanel!
    private var container: PassthroughContainer!
    private var pollTimer: Timer?

    init(counter: Counter) {
        self.counter = counter
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
        let hosting = NSHostingView(rootView: NotchView(counter: counter, geo: geo))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

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
            hosting.rootView = NotchView(counter: counter, geo: geo)
            hosting.frame = container.bounds
        }
        updateActiveRect()
    }

    /// Clickable region, in container coordinates.
    private func updateActiveRect() {
        let size = counter.isOpen ? geo.openSize : geo.closedSize
        container.activeRect = NSRect(x: geo.leadingOffset(open: counter.isOpen),
                                      y: geo.windowSize.height - size.height,
                                      width: size.width,
                                      height: size.height)
    }

    private func startTracking() {
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func updateHover() {
        let mouse = NSEvent.mouseLocation
        var rect = geo.shapeRectOnScreen(open: counter.isOpen)
        if counter.isOpen {
            rect = rect.insetBy(dx: -10, dy: -10)   // grace area so it doesn't snap shut at the edges
        }
        let inside = rect.contains(mouse)
        guard inside != counter.isOpen else { return }

        counter.isOpen = inside
        if !inside { counter.confirmingReset = false }
        updateActiveRect()
    }
}
