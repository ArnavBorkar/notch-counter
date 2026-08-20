import AppKit

/// How much room the panel needs right now.
enum PanelMode {
    case status     // connecting / failed
    case auth       // login
    case setup      // pasting a connection string
    case board      // the kanban
}

/// Physical + visual measurements of the notch we draw into.
struct NotchGeometry {
    let screen: NSScreen
    /// Width of the physical notch (or a stand-in on notchless Macs).
    let notchWidth: CGFloat
    /// Height of the menu bar / notch strip.
    let notchHeight: CGFloat
    /// How far the idle shape reaches past the right edge of the notch — today's outreach.
    let tail: CGFloat = 46
    /// …and past the left edge — tasks still open across the team.
    let leadingTail: CGFloat = 46

    /// Idle: the notch, widened both ways. Never taller than the menu bar,
    /// so it can't cover anything in the app below.
    var closedSize: CGSize {
        CGSize(width: leadingTail + notchWidth + tail + 2 * Style.topFlare, height: notchHeight)
    }

    func openSize(_ mode: PanelMode) -> CGSize {
        switch mode {
        case .status:
            return CGSize(width: 380, height: notchHeight + 110)
        case .auth:
            return CGSize(width: 460, height: notchHeight + 172)
        case .setup:
            return CGSize(width: 520, height: notchHeight + 196)
        case .board:
            return CGSize(width: min(1240, screen.frame.width - 96),
                          height: notchHeight + 468)
        }
    }

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]

        var width: CGFloat = 200
        var height: CGFloat = 32

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            width = right.minX - left.maxX
            height = screen.safeAreaInsets.top
        } else if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
        }

        return NotchGeometry(screen: screen, notchWidth: width, notchHeight: height)
    }

    /// The visible shape in screen coordinates. Idle hangs off the right of the notch;
    /// expanded is centred on it.
    func shapeRectOnScreen(open: Bool, mode: PanelMode) -> NSRect {
        let f = screen.frame
        let size = open ? openSize(mode) : closedSize
        let x = open
            ? f.midX - size.width / 2
            : f.midX - notchWidth / 2 - leadingTail - Style.topFlare
        return NSRect(x: x, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    /// Window is big enough for every state; the shape is drawn inside it at the right offset.
    var windowFrame: NSRect {
        shapeRectOnScreen(open: false, mode: .board)
            .union(shapeRectOnScreen(open: true, mode: .setup))
            .union(shapeRectOnScreen(open: true, mode: .board))
    }

    var windowSize: CGSize { windowFrame.size }

    /// Distance from the window's leading edge to the shape's leading edge.
    func leadingOffset(open: Bool, mode: PanelMode) -> CGFloat {
        shapeRectOnScreen(open: open, mode: mode).minX - windowFrame.minX
    }
}

enum Style {
    static let topFlare: CGFloat = 8          // inverted top corner radius
    static let bottomRadius: CGFloat = 13
    static let expandedRadius: CGFloat = 22
}
