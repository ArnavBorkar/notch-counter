import AppKit

/// Physical + visual measurements of the notch we draw into.
struct NotchGeometry {
    let screen: NSScreen
    /// Width of the physical notch (or a stand-in on notchless Macs).
    let notchWidth: CGFloat
    /// Height of the menu bar / notch strip.
    let notchHeight: CGFloat
    /// How far the idle shape reaches past the right edge of the notch — this is where the number sits.
    let tail: CGFloat = 46

    /// Idle: the notch, widened to the right. Never taller than the menu bar,
    /// so it can't cover anything in the app below.
    var closedSize: CGSize {
        CGSize(width: notchWidth + tail + 2 * Style.topFlare, height: notchHeight)
    }
    /// Hovered: wide enough for the controls, dropping just below the menu bar.
    var openSize: CGSize {
        CGSize(width: 300, height: notchHeight + 62)
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
    /// hovered is centred on it.
    func shapeRectOnScreen(open: Bool) -> NSRect {
        let f = screen.frame
        let size = open ? openSize : closedSize
        let x = open
            ? f.midX - size.width / 2
            : f.midX - notchWidth / 2 - Style.topFlare      // straight left edge meets the notch edge
        return NSRect(x: x, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    /// Window covers both states; the shape is drawn inside it at the right offset.
    var windowFrame: NSRect {
        shapeRectOnScreen(open: false).union(shapeRectOnScreen(open: true))
    }

    var windowSize: CGSize { windowFrame.size }

    /// Distance from the window's leading edge to the shape's leading edge.
    func leadingOffset(open: Bool) -> CGFloat {
        shapeRectOnScreen(open: open).minX - windowFrame.minX
    }
}

enum Style {
    static let topFlare: CGFloat = 8      // inverted top corner radius
    static let bottomRadius: CGFloat = 13
}
