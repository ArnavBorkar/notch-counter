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
            // aura underneath: the black fill masks its inner half, so the glow
            // only ever spills outward and the notch interior stays black
            if app.glowing {
                NotchAura(bottomRadius: app.expanded ? Style.expandedRadius : Style.bottomRadius)
                    .transition(.opacity)
            }

            NotchShape(bottomRadius: app.expanded ? Style.expandedRadius : Style.bottomRadius)
                .fill(Color.black)
            content
        }
        .frame(width: size.width, height: size.height)
        .offset(x: geo.leadingOffset(open: app.expanded, mode: mode))
        .frame(width: geo.windowSize.width, height: geo.windowSize.height, alignment: .topLeading)
        .animation(popSpring, value: app.expanded)
        .animation(popSpring, value: app.phase)
        .animation(.easeOut(duration: 0.25), value: app.updateAvailable)
        .animation(.easeInOut(duration: 0.5), value: app.winking)
        .animation(.easeInOut(duration: 0.45), value: app.glowing)
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
                if app.pulsing {
                    DayPulse(day: app.daysSinceStart)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 3.5) {
                        if app.updateAvailable {
                            Circle()
                                .fill(Palette.accent)
                                .frame(width: 5, height: 5)
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text("\(app.daysSinceStart)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.82))
                            .contentTransition(.numericText())
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: geo.leadingTail)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: app.pulsing)

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
            .contentShape(Rectangle())
            .onTapGesture { app.bump(1) }
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
