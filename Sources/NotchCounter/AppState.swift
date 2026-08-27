import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case setup              // no database URL yet
        case connecting
        case login
        case board
        case failed(String)
    }

    // Presentation
    @Published var phase: Phase = .connecting
    @Published var isOpen = false          // pointer is over the notch
    @Published var pinned = false          // clicked into the panel — stays open
    @Published var confirmingReset = false
    /// The card whose details are open, if any.
    @Published var openTaskID: UUID?
    @Published var banner: String?
    /// The idle number is briefly a face, to pull your eye back to outreach.
    @Published var winking = false
    /// …the left one warms and pings.
    @Published var pulsing = false
    /// The band of light crawling round the outline.
    @Published var glowing = false
    @Published var update: AppRelease?
    @Published var updateDismissed = false
    @Published var updateFailure: String?
    @Published var installingUpdate = false
    @Published private(set) var checkingForUpdate = false
    @Published private(set) var updateCheckMessage: String?
    @Published private(set) var nudgesEnabled = UserDefaults.standard.object(forKey: "nudges.enabled") as? Bool ?? true

    // Data
    @Published var me: BoardUser?
    @Published var users: [BoardUser] = []
    @Published var tasks: [BoardTask] = []
    @Published var myCount = 0
    @Published var teamCounts: [UUID: Int] = [:]

    private var db: Database?
    private var poller: Task<Void, Never>?
    private var nudger: Task<Void, Never>?
    private var updateChecker: Task<Void, Never>?

    /// Bumped on every local edit. A fetch that started before the current value
    /// is stale by definition — it was read before the edit reached the server —
    /// so its result is dropped rather than painted over what you just did.
    private var edits = 0
    private var writesInFlight = 0
    private var lastUsersFetch = Date.distantPast
    private let sessionKey = "session.userID"

    var expanded: Bool { isOpen || pinned }

    init() {
        if let url = Config.databaseURL() {
            connect(to: url, remember: false)
        } else {
            phase = .setup
        }
        startNudging()
        startUpdateChecks()
    }

    // MARK: - Updates

    private func startUpdateChecks() {
        updateChecker?.cancel()
        updateChecker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdate()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    func checkForUpdate(showFeedback: Bool = false) async {
        if showFeedback {
            guard !checkingForUpdate else { return }
            checkingForUpdate = true
            updateCheckMessage = nil
        }
        defer {
            if showFeedback { checkingForUpdate = false }
        }

        do {
            if let release = try await Updater.check() {
                if release != update || showFeedback { updateDismissed = false }
                update = release
            } else {
                update = nil
                if showFeedback {
                    updateCheckMessage = "You're up to date — version \(Updater.currentVersion)"
                }
            }
        } catch {
            if showFeedback {
                updateCheckMessage = "Couldn't check for updates"
            }
            // A failed automatic check is not worth interrupting anyone over.
        }
    }

    func installUpdate() {
        guard let release = update, !installingUpdate else { return }
        installingUpdate = true
        updateFailure = nil
        updateCheckMessage = nil
        Task {
            do {
                Updater.installedTag = release.tag
                try await Updater.install(release)
                NSApp.terminate(nil)
            } catch {
                installingUpdate = false
                updateFailure = error.localizedDescription
            }
        }
    }

    var updateAvailable: Bool { update != nil }

    func toggleNudges() {
        nudgesEnabled.toggle()
        UserDefaults.standard.set(nudgesEnabled, forKey: "nudges.enabled")
        if !nudgesEnabled { winking = false; pulsing = false; glowing = false }
    }

    private func startNudging() {
        nudger?.cancel()
        nudger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8 * 60))
                guard let self, !Task.isCancelled else { return }
                guard self.nudgesEnabled, !self.expanded, self.phase == .board else { continue }
                // staggered: the outline lights first, then the face, then the day
                self.glowing = true
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                self.winking = true
                Haptics.nudge()
                try? await Task.sleep(for: .milliseconds(700))
                self.pulsing = true

                try? await Task.sleep(for: .seconds(3))
                self.winking = false
                self.pulsing = false
                try? await Task.sleep(for: .milliseconds(600))
                self.glowing = false
            }
        }
    }

    // MARK: - Connection

    func connect(to urlString: String, remember: Bool) {
        phase = .connecting
        Task {
            do {
                let database = try Database(urlString: urlString)
                database.start()
                try await database.bootstrap()
                db = database
                if remember { Config.save(databaseURL: urlString) }

                if let raw = UserDefaults.standard.string(forKey: sessionKey),
                   let id = UUID(uuidString: raw),
                   let user = try await database.user(id: id) {
                    me = user
                    phase = .board
                    await refresh()
                } else {
                    phase = .login
                }
                startPolling()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func forgetDatabase() {
        poller?.cancel()
        db?.shutdown()
        db = nil
        Config.clearSavedDatabaseURL()
        UserDefaults.standard.removeObject(forKey: sessionKey)
        me = nil
        tasks = []
        users = []
        phase = .setup
    }

    // MARK: - Accounts

    func logIn(email: String, pin: String) async {
        guard let db else { return }
        do {
            let user = try await db.logIn(email: email, pin: pin)
            UserDefaults.standard.set(user.id.uuidString, forKey: sessionKey)
            me = user
            phase = .board
            Haptics.success()
            await refresh()
        } catch {
            banner = error.localizedDescription
        }
    }

    func signUp(email: String, name: String, pin: String) async {
        guard let db else { return }
        do {
            let user = try await db.signUp(email: email, name: name, pin: pin)
            UserDefaults.standard.set(user.id.uuidString, forKey: sessionKey)
            me = user
            phase = .board
            Haptics.success()
            await refresh()
        } catch {
            banner = error.localizedDescription
        }
    }

    func logOut() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        me = nil
        tasks = []
        phase = .login
    }

    // MARK: - Sync

    private func startPolling() {
        poller?.cancel()
        poller = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let open = self.expanded
                try? await Task.sleep(for: .seconds(open ? 3 : 25))
                guard !Task.isCancelled, self.phase == .board else { continue }
                await self.refresh()
            }
        }
    }

    /// Opening the panel shouldn't show you a board that's up to 25s stale.
    func panelDidOpen() {
        guard phase == .board else { return }
        Task { await refresh() }
    }

    func refresh() async {
        guard let db, let me else { return }
        let seenEdits = edits

        do {
            // Two round trips, not four: today's counts come from one table read,
            // and the roster only changes when someone signs up.
            async let taskFetch = db.tasks()
            async let teamFetch = db.teamOutreachToday()

            var freshUsers: [BoardUser]?
            if users.isEmpty || Date().timeIntervalSince(lastUsersFetch) > 60 {
                freshUsers = try await db.users()
            }
            let freshTasks = try await taskFetch
            let freshTeam = try await teamFetch

            banner = nil

            // Someone edited while this was in flight — their version is newer than
            // ours. Drop it; the write's own refresh will bring the truth along.
            guard edits == seenEdits, writesInFlight == 0 else { return }

            tasks = freshTasks
            teamCounts = freshTeam
            myCount = freshTeam[me.id] ?? 0
            if let freshUsers {
                users = freshUsers
                lastUsersFetch = Date()
            }
        } catch {
            banner = "Offline — \(error.localizedDescription)"
        }
    }

    // MARK: - Board actions (optimistic, then reconciled by the next refresh)

    /// Where the server will put a card appended to this column.
    private func nextLocalPosition(in status: TaskStatus) -> Double {
        (tasks.filter { $0.status == status }.map(\.position).max() ?? 0) + 1
    }

    func addTask(title: String, assignee: UUID?) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let db, let me else { return }
        let optimistic = BoardTask(id: UUID(), title: title, status: .backlog, important: false,
                                   assigneeID: assignee, position: nextLocalPosition(in: .backlog),
                                   createdAt: Date())
        tasks.append(optimistic)
        Haptics.add()
        run { try await db.addTask(title: title, status: .backlog, assignee: assignee, createdBy: me.id) }
    }

    func move(_ task: BoardTask, to status: TaskStatus) {
        guard status != task.status else { return }
        move(task, to: status, above: nil)
    }

    /// Drop `task` directly above `target` — or at the bottom when target is nil.
    /// Positions are midpoints between neighbours, so only the dragged row is written.
    func move(_ task: BoardTask, to status: TaskStatus, above target: BoardTask?) {
        guard let db else { return }
        let siblings = tasks(in: status).filter { $0.id != task.id }

        let position: Double
        if let target, let index = siblings.firstIndex(where: { $0.id == target.id }) {
            let below = target.position
            let above = index > 0 ? siblings[index - 1].position : below - 2
            position = (above + below) / 2
        } else {
            position = (siblings.map(\.position).max() ?? 0) + 1
        }

        guard status != task.status || position != task.position else { return }

        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i].status = status
            tasks[i].position = position
        }
        Haptics.move()
        run { try await db.reposition(task.id, status: status, position: position) }
    }

    func toggleImportant(_ task: BoardTask) {
        guard let db else { return }
        let flag = !task.important
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].important = flag }
        Haptics.star()
        run { try await db.setImportant(task.id, flag) }
    }

    func assign(_ task: BoardTask, to user: UUID?) {
        guard let db else { return }
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].assigneeID = user }
        run { try await db.assign(task.id, to: user) }
    }

    func rename(_ task: BoardTask, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let db, !title.isEmpty, title != task.title else { return }
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].title = title }
        run { try await db.rename(task.id, to: title) }
    }

    func setDescription(_ task: BoardTask, to text: String) {
        guard let db, text != task.description else { return }
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].description = text }
        run { try await db.setDescription(task.id, to: text) }
    }

    var openTask: BoardTask? {
        guard let openTaskID else { return nil }
        return tasks.first { $0.id == openTaskID }
    }

    func delete(_ task: BoardTask) {
        guard let db else { return }
        tasks.removeAll { $0.id == task.id }
        if openTaskID == task.id { openTaskID = nil }
        Haptics.destroy()
        run { try await db.delete(task.id) }
    }

    // MARK: - Outreach counter

    func bump(_ delta: Int) {
        guard let db, let me else { return }
        myCount = max(0, myCount + delta)
        teamCounts[me.id] = myCount
        Haptics.tick()
        run { _ = try await db.bumpOutreach(for: me.id, by: delta) }
    }

    func resetCount() {
        guard let db, let me else { return }
        myCount = 0
        teamCounts[me.id] = 0
        confirmingReset = false
        Haptics.destroy()
        run { _ = try await db.resetOutreach(for: me.id) }
    }

    var teamTotal: Int { teamCounts.values.reduce(0, +) }

    /// What the team still owes today.
    var tasksLeft: Int { tasks.filter { $0.status != .done }.count }

    /// Days on the clock — shown in the notch, left of the camera.
    var daysSinceStart: Int {
        let start = Config.countingSince()
        let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
        return max(0, days)
    }

    func tasks(in status: TaskStatus) -> [BoardTask] {
        tasks.filter { $0.status == status }
            .sorted { lhs, rhs in
                if lhs.important != rhs.important { return lhs.important }
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func user(_ id: UUID?) -> BoardUser? {
        guard let id else { return nil }
        return users.first { $0.id == id }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        edits += 1
        writesInFlight += 1
        Task {
            do {
                try await work()
            } catch {
                banner = error.localizedDescription
            }
            writesInFlight -= 1
            await refresh()
        }
    }
}

extension AppState {
    var panelMode: PanelMode {
        switch phase {
        case .board:   return .board
        case .login:   return .auth
        case .setup:   return .setup
        default:       return .status
        }
    }
}
