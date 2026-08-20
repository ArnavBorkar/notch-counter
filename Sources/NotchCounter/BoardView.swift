import SwiftUI

struct BoardView: View {
    @ObservedObject var app: AppState
    @State private var draft = ""
    @State private var draftAssignee: UUID?
    @FocusState private var draftFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                composer
                HStack(alignment: .top, spacing: 10) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        ColumnView(app: app, status: status)
                    }
                }
            }
            OutreachRail(app: app)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .padding(.top, 10)
        .onAppear { draftAssignee = draftAssignee ?? app.me?.id }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            DarkField(placeholder: "Add a task…", text: $draft) { submit() }
                .focused($draftFocused)

            AssigneePicker(users: app.users, onPick: { draftAssignee = $0 }) {
                HStack(spacing: 6) {
                    Avatar(user: app.user(draftAssignee), size: 18)
                    Text(app.user(draftAssignee)?.name ?? "Unassigned")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Palette.dim)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Palette.dim)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06)))
            }
            .fixedSize()

            PillButton(title: "Add", tint: Palette.accent) { submit() }

            if let banner = app.banner {
                Text(banner)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.danger)
                    .lineLimit(1)
            }
        }
    }

    private func submit() {
        app.addTask(title: draft, assignee: draftAssignee)
        draft = ""
        draftFocused = true
    }
}

struct ColumnView: View {
    @ObservedObject var app: AppState
    let status: TaskStatus
    @State private var targeted = false

    private var items: [BoardTask] { app.tasks(in: status) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(status.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(Palette.dim)
                Spacer()
            }
            .padding(.horizontal, 4)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 7) {
                    ForEach(items) { task in
                        TaskCard(app: app, task: task)
                    }
                    if items.isEmpty {
                        Text("Nothing here")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.white.opacity(0.22))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(targeted ? Palette.cardHover : Palette.column)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(targeted ? Palette.accent : .clear, lineWidth: 1.5)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let id = UUID(uuidString: raw),
                  let task = app.tasks.first(where: { $0.id == id }) else { return false }
            app.move(task, to: status)
            return true
        } isTargeted: { targeted = $0 }
        .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

struct TaskCard: View {
    @ObservedObject var app: AppState
    let task: BoardTask
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(task.title)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                AssigneePicker(users: app.users, onPick: { app.assign(task, to: $0) }) {
                    Avatar(user: app.user(task.assigneeID), size: 18)
                }

                IconButton(symbol: task.important ? "star.fill" : "star",
                           size: 18,
                           tint: task.important ? Palette.star : .white) {
                    app.toggleImportant(task)
                }

                Spacer(minLength: 0)

                if hovering {
                    if let previous = task.status.previous {
                        IconButton(symbol: "arrow.left", size: 18) { app.move(task, to: previous) }
                    }
                    if let next = task.status.next {
                        IconButton(symbol: "arrow.right", size: 18) { app.move(task, to: next) }
                    }
                    IconButton(symbol: "trash", size: 18, tint: Palette.danger) { app.delete(task) }
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovering ? Palette.cardHover : Palette.card)
        )
        .overlay(alignment: .leading) {
            if task.important {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.star)
                    .frame(width: 2.5)
                    .padding(.vertical, 6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .draggable(task.id.uuidString)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

struct OutreachRail: View {
    @ObservedObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reached out today")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.dim)
                .textCase(.uppercase)
                .kerning(0.4)

            Spacer(minLength: 8)

            if app.confirmingReset {
                VStack(spacing: 8) {
                    Text("Reset your count to 0?")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        PillButton(title: "Cancel") { app.confirmingReset = false }
                        PillButton(title: "Reset", tint: Palette.danger) { app.resetCount() }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    Text("\(app.myCount)")
                        .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: Double(app.myCount)))

                    HStack(spacing: 12) {
                        CircleButton(symbol: "minus") { app.bump(-1) }
                        CircleButton(symbol: "plus") { app.bump(1) }
                    }

                    Button { app.confirmingReset = true } label: {
                        Text("Reset")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.dim)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 8)

            Divider().overlay(Palette.hairline)

            HStack(spacing: 6) {
                Text("Team today")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Palette.dim)
                Spacer()
                Text("\(app.teamTotal)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.vertical, 8)

            Divider().overlay(Palette.hairline)

            HStack(spacing: 7) {
                Avatar(user: app.me, size: 20)
                Text(app.me?.name ?? "")
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
                IconButton(symbol: "rectangle.portrait.and.arrow.right", size: 20) { app.logOut() }
            }
            .padding(.top, 8)
        }
        .frame(width: 178)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.column))
    }
}
