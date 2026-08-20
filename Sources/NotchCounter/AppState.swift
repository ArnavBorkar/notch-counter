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

    // Data
    @Published var me: BoardUser?
    @Published var users: [BoardUser] = []
    @Published var tasks: [BoardTask] = []
    @Published var myCount = 0
    @Published var teamCounts: [UUID: Int] = [:]

    private var db: Database?
    private var poller: Task<Void, Never>?
    private let sessionKey = "session.userID"

    var expanded: Bool { isOpen || pinned }

    init() {
        if let url = Config.databaseURL() {
            connect(to: url, remember: false)
        } else {
            phase = .setup
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

    func refresh() async {
        guard let db, let me else { return }
        do {
            async let tasks = db.tasks()
            async let users = db.users()
            async let count = db.outreachCount(for: me.id)
            async let team = db.teamOutreachToday()
            self.tasks = try await tasks
            self.users = try await users
            self.myCount = try await count
            self.teamCounts = try await team
            if banner != nil { banner = nil }
        } catch {
            banner = "Offline — \(error.localizedDescription)"
        }
    }

    // MARK: - Board actions (optimistic, then reconciled by the next refresh)

    func addTask(title: String, assignee: UUID?) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let db, let me else { return }
        let optimistic = BoardTask(id: UUID(), title: title, status: .backlog, important: false,
                                   assigneeID: assignee, position: .greatestFiniteMagnitude,
                                   createdAt: Date())
        tasks.append(optimistic)
        run { try await db.addTask(title: title, status: .backlog, assignee: assignee, createdBy: me.id) }
    }

    func move(_ task: BoardTask, to status: TaskStatus) {
        guard let db, status != task.status else { return }
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].status = status }
        run { try await db.move(task.id, to: status) }
    }

    func toggleImportant(_ task: BoardTask) {
        guard let db else { return }
        let flag = !task.important
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i].important = flag }
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
        run { try await db.delete(task.id) }
    }

    // MARK: - Outreach counter

    func bump(_ delta: Int) {
        guard let db, let me else { return }
        myCount = max(0, myCount + delta)
        teamCounts[me.id] = myCount
        run { _ = try await db.bumpOutreach(for: me.id, by: delta) }
    }

    func resetCount() {
        guard let db, let me else { return }
        myCount = 0
        teamCounts[me.id] = 0
        confirmingReset = false
        run { _ = try await db.resetOutreach(for: me.id) }
    }

    var teamTotal: Int { teamCounts.values.reduce(0, +) }

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
        Task {
            do {
                try await work()
                await refresh()
            } catch {
                banner = error.localizedDescription
                await refresh()
            }
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
