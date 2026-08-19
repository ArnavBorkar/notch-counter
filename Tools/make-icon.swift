#!/usr/bin/env swift
// Renders AppIcon.icns: a dark screen with a notch bitten out of its top edge,
// showing a number. Run: swift Tools/make-icon.swift
import AppKit

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let digits = "7"

func notchPath(in r: CGRect, flare: CGFloat, radius: CGFloat) -> CGPath {
    // same silhouette the app draws: concave shoulders, rounded bottom corners
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX, y: r.maxY))
    p.addQuadCurve(to: CGPoint(x: r.minX + flare, y: r.maxY - flare),
                   control: CGPoint(x: r.minX + flare, y: r.maxY))
    p.addLine(to: CGPoint(x: r.minX + flare, y: r.minY + radius))
    p.addQuadCurve(to: CGPoint(x: r.minX + flare + radius, y: r.minY),
                   control: CGPoint(x: r.minX + flare, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - flare - radius, y: r.minY))
    p.addQuadCurve(to: CGPoint(x: r.maxX - flare, y: r.minY + radius),
                   control: CGPoint(x: r.maxX - flare, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - flare, y: r.maxY - flare))
    p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                   control: CGPoint(x: r.maxX - flare, y: r.maxY))
    p.closeSubpath()
    return p
}

func render(px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext

    // squircle body
    let inset = s * 0.055
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let colors = [NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.19, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.04, alpha: 1).cgColor]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // hairline rim so it reads on dark wallpapers
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokePath()
    ctx.restoreGState()

    // bite the notch out of the top edge
    let nw = body.width * 0.44
    let nh = body.height * 0.13
    let notch = CGRect(x: body.midX - nw / 2, y: body.maxY - nh, width: nw, height: nh)
    ctx.saveGState()
    ctx.setBlendMode(.clear)
    ctx.addPath(notchPath(in: notch, flare: nh * 0.22, radius: nh * 0.55))
    ctx.fillPath()
    ctx.restoreGState()

    // the count
    let fontSize = s * 0.46
    let base = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor,
                      size: fontSize) ?? base
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: NSColor.white, .paragraphStyle: para,
    ]
    let str = NSAttributedString(string: digits, attributes: attrs)
    let textSize = str.size()
    let origin = CGPoint(x: body.midX - textSize.width / 2,
                         y: body.midY - textSize.height / 2 - s * 0.035)
    str.draw(at: origin)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: out)
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, px) in sizes {
    try! render(px: px).write(to: out.appendingPathComponent("\(name).png"))
}
print("wrote \(out.path)")
