import SwiftUI

private let popSpring = Animation.spring(response: 0.33, dampingFraction: 0.78)

struct NotchView: View {
    @ObservedObject var counter: Counter
    let geo: NotchGeometry

    private var size: CGSize { counter.isOpen ? geo.openSize : geo.closedSize }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape()
                .fill(Color.black)
                .shadow(color: .black.opacity(counter.isOpen ? 0.5 : 0), radius: 12, y: 6)
            content
        }
        .frame(width: size.width, height: size.height)
        .offset(x: geo.leadingOffset(open: counter.isOpen))
        .frame(width: geo.windowSize.width, height: geo.windowSize.height, alignment: .topLeading)
        .animation(popSpring, value: counter.isOpen)
        .animation(popSpring, value: counter.confirmingReset)
    }

    @ViewBuilder
    private var content: some View {
        if counter.isOpen {
            Group {
                if counter.confirmingReset { resetConfirmation } else { controls }
            }
            .padding(.top, geo.notchHeight)      // stay clear of the camera housing
            .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        } else {
            // number sits in the strip to the right of the notch
            HStack(spacing: 0) {
                Color.clear.frame(width: Style.topFlare + geo.notchWidth)
                Text("\(counter.value)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .frame(width: geo.tail)
                Spacer(minLength: 0)
            }
            .frame(height: geo.notchHeight)
            .transition(.opacity)
        }
    }

    private var controls: some View {
        VStack(spacing: 2) {
            HStack(spacing: 14) {
                CircleButton(symbol: "minus") { counter.decrement() }
                Text("\(counter.value)")
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: Double(counter.value)))
                    .frame(minWidth: 84)
                CircleButton(symbol: "plus") { counter.increment() }
            }
            Button { counter.confirmingReset = true } label: {
                Text("Reset")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var resetConfirmation: some View {
        VStack(spacing: 8) {
            Text("Reset counter to 0?")
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            HStack(spacing: 8) {
                PillButton(title: "Cancel", tint: .white.opacity(0.14), fg: .white.opacity(0.85)) {
                    counter.confirmingReset = false
                }
                PillButton(title: "Reset", tint: Color(red: 0.92, green: 0.25, blue: 0.24), fg: .white) {
                    counter.reset()
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct CircleButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(hovering ? 0.26 : 0.13)))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.06 : 1)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: hovering)
        .onHover { hovering = $0 }
    }
}

private struct PillButton: View {
    let title: String
    let tint: Color
    let fg: Color
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
