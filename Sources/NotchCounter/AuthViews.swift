import SwiftUI

struct SetupView: View {
    @ObservedObject var app: AppState
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect your database")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Paste the Postgres connection string for your team's board. It's stored in your login keychain, never in the repo.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Palette.dim)
                .fixedSize(horizontal: false, vertical: true)

            DarkField(placeholder: "postgresql://user:password@host/db?sslmode=require", text: $url) {
                connect()
            }

            HStack {
                Text("or drop it in ~/.config/notch-counter/config.json")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                PillButton(title: "Connect", tint: Palette.accent) { connect() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .padding(.top, 12)
    }

    private func connect() {
        guard !url.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        app.connect(to: url, remember: true)
    }
}

struct LoginView: View {
    @ObservedObject var app: AppState
    @State private var creating = false
    @State private var email = ""
    @State private var name = ""
    @State private var pin = ""

    private var pinIsValid: Bool { pin.count == 4 && pin.allSatisfy(\.isNumber) }
    private var canSubmit: Bool {
        email.contains("@") && pinIsValid && (!creating || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(creating ? "Create an account" : "Log in")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button(creating ? "I already have one" : "Create an account") {
                    creating.toggle()
                    app.banner = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(Palette.accent)
            }

            if creating {
                DarkField(placeholder: "Name", text: $name)
            }
            DarkField(placeholder: "Email", text: $email) { submit() }
            DarkField(placeholder: "4-digit PIN", text: $pin, isSecure: true) { submit() }
                .onChange(of: pin) { _, value in
                    pin = String(value.filter(\.isNumber).prefix(4))
                }

            if let banner = app.banner {
                Text(banner)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.danger)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Change database") { app.forgetDatabase() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
                PillButton(title: creating ? "Create" : "Log in",
                           tint: canSubmit ? Palette.accent : .white.opacity(0.12)) { submit() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .padding(.top, 12)
    }

    private func submit() {
        guard canSubmit else { return }
        Task {
            if creating {
                await app.signUp(email: email, name: name, pin: pin)
            } else {
                await app.logIn(email: email, pin: pin)
            }
            pin = ""
        }
    }
}

struct StatusView: View {
    let title: String
    var detail: String?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            if let detail {
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.dim)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                PillButton(title: action.title, tint: Palette.accent) { action.run() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}
