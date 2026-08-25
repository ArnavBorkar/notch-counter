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
    @Published var banner: String?
    /// The idle number is briefly a face, to pull your eye back to outreach.
    @Published var winking = false
    /// …and the left one catches fire.
    @Published var flaming = false
    @Published var update: AppRelease?
    @Published var updateDismissed = false
    @Published var updateFailure: String?
    @Published var installingUpdate = false
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

    func checkForUpdate() async {
        do {
            if let release = try await Updater.check() {
                if release != update { updateDismissed = false }
                update = release
            } else {
                update = nil
            }
        } catch {
            // a failed check is not worth interrupting anyone over
        }
    }

    func installUpdate() {
        guard let release = update, !installingUpdate else { return }
        installingUpdate = true
        updateFailure = nil
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
        if !nudgesEnabled { winking = false; flaming = false }
    }

    private func startNudging() {
        nudger?.cancel()
        nudger = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, !Task.isCancelled else { return }
                guard self.nudgesEnabled, !self.expanded, self.phase == .board else { continue }
                self.winking = true
                self.flaming = true
                Haptics.nudge()
                try? await Task.sleep(for: .seconds(2.6))
                self.winking = false
                self.flaming = false
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
        guard let db, status != task.status else { return }
        if let i = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[i].status = status
            tasks[i].position = nextLocalPosition(in: status)   // land where it'll settle
        }
        Haptics.move()
        run { try await db.move(task.id, to: status) }
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

    func delete(_ task: BoardTask) {
        guard let db else { return }
        tasks.removeAll { $0.id == task.id }
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
