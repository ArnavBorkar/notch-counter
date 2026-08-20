import SwiftUI

/// The notch silhouette: concave shoulders at the top, rounded corners at the bottom.
struct NotchShape: Shape {
    var topFlare: CGFloat = Style.topFlare
    var bottomRadius: CGFloat = Style.bottomRadius

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let flare = min(topFlare, w / 2)
        let radius = min(bottomRadius, (w - 2 * flare) / 2, h)

        var p = Path()
        p.move(to: CGPoint(x: 0, y: 0))
        // left shoulder, curving inward
        p.addQuadCurve(to: CGPoint(x: flare, y: flare),
                       control: CGPoint(x: flare, y: 0))
        p.addLine(to: CGPoint(x: flare, y: h - radius))
        p.addQuadCurve(to: CGPoint(x: flare + radius, y: h),
                       control: CGPoint(x: flare, y: h))
        p.addLine(to: CGPoint(x: w - flare - radius, y: h))
        p.addQuadCurve(to: CGPoint(x: w - flare, y: h - radius),
                       control: CGPoint(x: w - flare, y: h))
        p.addLine(to: CGPoint(x: w - flare, y: flare))
        // right shoulder
        p.addQuadCurve(to: CGPoint(x: w, y: 0),
                       control: CGPoint(x: w - flare, y: 0))
        p.closeSubpath()
        return p
    }
}
