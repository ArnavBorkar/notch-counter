import SwiftUI

/// The Jira-ish card view: title, a free-text body, and the card's properties.
/// Edits autosave shortly after you stop typing, so closing never loses work.
struct TaskDetailView: View {
    @ObservedObject var app: AppState
    let task: BoardTask

    @State private var draftTitle: String
    @State private var draftDetails: String
    @State private var saver: Task<Void, Never>?
    @State private var savedAt: Date?
    @State private var confirmingDelete = false
    @FocusState private var detailsFocused: Bool

    init(app: AppState, task: BoardTask) {
        self.app = app
        self.task = task
        _draftTitle = State(initialValue: task.title)
        _draftDetails = State(initialValue: task.description)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            titleField
            detailsEditor
            footer
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(Palette.column))
        .onDisappear { saver?.cancel(); commit() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button { app.move(task, to: status) } label: {
                    Text(status.title)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(task.status == status ? .white : Palette.dim)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(task.status == status
                                           ? Palette.accent.opacity(0.85)
                                           : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if let savedAt, Date().timeIntervalSince(savedAt) < 3 {
                Text("Saved")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Palette.dim)
                    .transition(.opacity)
            }

            IconButton(symbol: task.important ? "star.fill" : "star",
                       size: 22,
                       tint: task.important ? Palette.star : .white) {
                app.toggleImportant(task)
            }

            IconButton(symbol: "xmark", size: 22) { close() }
        }
    }

    private var titleField: some View {
        TextField("Title", text: $draftTitle, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1...3)
            .onChange(of: draftTitle) { _, _ in scheduleSave() }
    }

    private var detailsEditor: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Details")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.dim)
                .textCase(.uppercase)
                .kerning(0.4)

            ZStack(alignment: .topLeading) {
                if draftDetails.isEmpty && !detailsFocused {
                    Text("Notes, links, acceptance criteria — whatever the card needs.")
                        .font(.system(size: 12.5, design: .rounded))
                        .foregroundStyle(.white.opacity(0.22))
                        .padding(.top, 8)
                        .padding(.leading, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draftDetails)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .focused($detailsFocused)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .onChange(of: draftDetails) { _, _ in scheduleSave() }
            }
            .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(detailsFocused ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: 1)
            )
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            AssigneePicker(users: app.users, onPick: { app.assign(task, to: $0) }) {
                HStack(spacing: 6) {
                    Avatar(user: app.user(task.assigneeID), size: 20)
                    Text(app.user(task.assigneeID)?.name ?? "Unassigned")
                        .font(.system(size: 11.5, design: .rounded))
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

            Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))

            Spacer(minLength: 0)

            if confirmingDelete {
                Text("Delete this card?")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                PillButton(title: "Cancel") { confirmingDelete = false }
                PillButton(title: "Delete", tint: Palette.danger) { app.delete(task) }
            } else {
                PillButton(title: "Delete", tint: Palette.danger.opacity(0.5)) {
                    Haptics.warn()
                    confirmingDelete = true
                }
            }
        }
    }

    // MARK: - Saving

    private func scheduleSave() {
        saver?.cancel()
        saver = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        let titleChanged = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines) != task.title
        let detailsChanged = draftDetails != task.description
        guard titleChanged || detailsChanged else { return }

        if titleChanged { app.rename(task, to: draftTitle) }
        if detailsChanged { app.setDescription(task, to: draftDetails) }
        withAnimation { savedAt = Date() }
    }

    private func close() {
        saver?.cancel()
        commit()
        app.openTaskID = nil
    }
}
