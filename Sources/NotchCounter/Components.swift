import SwiftUI

enum Palette {
    static let card = Color.white.opacity(0.065)
    static let cardHover = Color.white.opacity(0.10)
    static let column = Color.white.opacity(0.035)
    static let hairline = Color.white.opacity(0.10)
    static let dim = Color.white.opacity(0.42)
    static let star = Color(red: 1.0, green: 0.78, blue: 0.28)
    static let danger = Color(red: 0.92, green: 0.28, blue: 0.26)
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.0)

    /// Fixed set so a person is the same colour on everyone's Mac, every launch.
    static let avatars: [Color] = [
        Color(red: 0.35, green: 0.66, blue: 0.98),   // blue
        Color(red: 0.36, green: 0.76, blue: 0.52),   // green
        Color(red: 0.95, green: 0.60, blue: 0.28),   // orange
        Color(red: 0.78, green: 0.50, blue: 0.94),   // purple
        Color(red: 0.94, green: 0.44, blue: 0.52),   // rose
        Color(red: 0.30, green: 0.74, blue: 0.78),   // teal
        Color(red: 0.86, green: 0.72, blue: 0.30),   // gold
        Color(red: 0.56, green: 0.60, blue: 0.94),   // indigo
    ]
}

struct Avatar: View {
    let user: BoardUser?
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Circle().fill(user == nil ? Color.white.opacity(0.10) : tint)
            if let user {
                Text(user.initials)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "person")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Palette.dim)
            }
        }
        .frame(width: size, height: size)
    }

    /// Stable colour per person, so faces are recognisable at a glance.
    /// Hashed from the UUID's bytes, not `hashValue` — that one is seeded per
    /// process, so it would repaint everyone on every launch.
    private var tint: Color {
        guard let user else { return .gray }
        var acc = 0
        withUnsafeBytes(of: user.id.uuid) { bytes in
            for byte in bytes { acc = (acc &* 31 &+ Int(byte)) & 0xFFFFFF }
        }
        return Palette.avatars[acc % Palette.avatars.count]
    }
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 22
    var tint: Color = .white
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tint.opacity(hovering ? 1 : 0.65))
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(hovering ? 0.14 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CircleButton: View {
    let symbol: String
    var size: CGFloat = 32
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(hovering ? 0.26 : 0.13)))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: hovering)
        .onHover { hovering = $0 }
    }
}

struct PillButton: View {
    let title: String
    var tint: Color = .white.opacity(0.14)
    var fg: Color = .white
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(fg)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(hovering ? 1 : 0.82)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Dark, borderless text field — the stock one looks wrong on pure black.
struct DarkField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure = false
    var onSubmit: () -> Void = {}

    var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 13, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.hairline, lineWidth: 1))
        .onSubmit(onSubmit)
    }
}

/// A `Menu` label flattens custom backgrounds, so the assignee picker pops an
/// AppKit menu from a plain button instead — the avatar keeps its colour.
struct AssigneePicker<Label: View>: View {
    let users: [BoardUser]
    let onPick: (UUID?) -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button {
            present()
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    private func present() {
        guard let window = NSApp.windows.first(where: { $0 is NotchPanel }),
              let view = window.contentView else { return }

        let handler = MenuHandler { raw in
            onPick((raw as? String).flatMap(UUID.init(uuidString:)))
        }
        MenuHandler.retained = handler   // one menu is open at a time

        let menu = NSMenu()
        let none = NSMenuItem(title: "Unassigned", action: #selector(MenuHandler.fire(_:)), keyEquivalent: "")
        none.target = handler
        menu.addItem(none)
        menu.addItem(.separator())
        for user in users {
            let item = NSMenuItem(title: user.name, action: #selector(MenuHandler.fire(_:)), keyEquivalent: "")
            item.representedObject = user.id.uuidString
            item.target = handler
            menu.addItem(item)
        }

        // pop it where the pointer is — that's the avatar the user just clicked
        let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        menu.popUp(positioning: nil, at: point, in: view)
    }
}

final class MenuHandler: NSObject {
    static var retained: MenuHandler?
    private let action: (Any?) -> Void
    init(action: @escaping (Any?) -> Void) { self.action = action }
    @objc func fire(_ sender: NSMenuItem) { action(sender.representedObject) }
}

/// The nudge: every so often the idle number turns into a small angry face —
/// brows down, glaring, with a shake — so outreach doesn't quietly slip.
struct NudgeFace: View {
    @State private var brow: CGFloat = 0        // 0 flat, 1 slammed down
    @State private var frown = false
    @State private var squint = false
    @State private var shake: CGFloat = 0
    @State private var glare: CGFloat = 0

    private let ink = Color(red: 0.98, green: 0.34, blue: 0.30)

    var body: some View {
        VStack(spacing: 2.6) {
            HStack(spacing: 5.5) {
                browShape(lean: 1)
                browShape(lean: -1)
            }
            HStack(spacing: 6.5) {
                eye
                eye
            }
            .offset(x: glare)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 6.5))
                path.addQuadCurve(to: CGPoint(x: 14, y: 6.5),
                                  control: CGPoint(x: 7, y: frown ? 0 : 5.5))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            .frame(width: 14, height: 7)
        }
        .offset(x: shake)
        .task { await perform() }
    }

    private func browShape(lean: Double) -> some View {
        Capsule()
            .fill(ink)
            .frame(width: 7, height: 1.8)
            .rotationEffect(.degrees(22 * lean * brow))
            .offset(y: brow * 0.7)
    }

    private var eye: some View {
        Capsule()
            .fill(ink)
            .frame(width: 4.5, height: squint ? 3 : 5.5)
    }

    private func perform() async {
        func pause(_ ms: UInt64) async { try? await Task.sleep(for: .milliseconds(ms)) }

        await pause(120)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.6)) {
            brow = 1; frown = true; squint = true
        }
        await pause(320)

        for _ in 0..<3 {                                  // seething
            withAnimation(.easeInOut(duration: 0.07)) { shake = 1.8 }
            await pause(70)
            withAnimation(.easeInOut(duration: 0.07)) { shake = -1.8 }
            await pause(70)
        }
        withAnimation(.easeInOut(duration: 0.08)) { shake = 0 }
        await pause(360)

        withAnimation(.easeInOut(duration: 0.4)) { glare = 2 }   // glaring at you
        await pause(420)
        withAnimation(.easeInOut(duration: 0.4)) { glare = -2 }
        await pause(420)
        withAnimation(.easeInOut(duration: 0.3)) { glare = 0 }
    }
}
