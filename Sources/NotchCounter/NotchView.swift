import SwiftUI

private let popSpring = Animation.spring(response: 0.36, dampingFraction: 0.82)

struct NotchView: View {
    @ObservedObject var app: AppState
    let geo: NotchGeometry

    private var mode: PanelMode { app.panelMode }
    private var size: CGSize { app.expanded ? geo.openSize(mode) : geo.closedSize }

    var body: some View {
        ZStack(alignment: .top) {
            // No drop shadow: it bleeds past the rounded corners and reads as a
            // smudged band down each side over light windows.
            NotchShape(bottomRadius: app.expanded ? Style.expandedRadius : Style.bottomRadius)
                .fill(Color.black)
            content
        }
        .frame(width: size.width, height: size.height)
        .offset(x: geo.leadingOffset(open: app.expanded, mode: mode))
        .frame(width: geo.windowSize.width, height: geo.windowSize.height, alignment: .topLeading)
        .animation(popSpring, value: app.expanded)
        .animation(popSpring, value: app.phase)
        .animation(.easeOut(duration: 0.16), value: app.confirmingReset)
    }

    @ViewBuilder
    private var content: some View {
        if app.expanded {
            expanded
                .padding(.top, geo.notchHeight)      // stay clear of the camera housing
                .transition(.opacity)
        } else {
            idle
        }
    }

    /// Idle: tasks left on the left of the notch, today's outreach on the right.
    private var idle: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Style.topFlare)

            Group {
                if app.flaming {
                    FlameNudge()
                        .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                } else {
                    Text("\(app.daysSinceStart)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.82))
                        .contentTransition(.numericText())
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: geo.leadingTail)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: app.flaming)

            Color.clear.frame(width: geo.notchWidth)

            Group {
                if app.winking {
                    NudgeFace()
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Text(app.me == nil ? "–" : "\(app.myCount)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: geo.tail)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: app.winking)

            Spacer(minLength: 0)
        }
        .frame(height: geo.notchHeight)
        .transition(.opacity)
    }

    @ViewBuilder
    private var expanded: some View {
        switch app.phase {
        case .setup:
            SetupView(app: app)
        case .connecting:
            StatusView(title: "Connecting…")
        case .failed(let message):
            StatusView(title: "Couldn't connect",
                       detail: message,
                       action: ("Change database", { app.forgetDatabase() }))
        case .login:
            LoginView(app: app)
        case .board:
            BoardView(app: app)
        }
    }
}
