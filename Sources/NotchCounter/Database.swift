import Foundation
import PostgresNIO
import NIOSSL
import CryptoKit

enum DatabaseError: LocalizedError {
    case badURL(String)
    case emailTaken
    case badCredentials
    case notFound

    var errorDescription: String? {
        switch self {
        case .badURL(let s):    return "Couldn't read that connection string: \(s)"
        case .emailTaken:       return "That email already has an account — try logging in."
        case .badCredentials:   return "Wrong email or PIN."
        case .notFound:         return "Not found."
        }
    }
}

/// Talks to Postgres (Neon in production, anything local in development).
final class Database: @unchecked Sendable {
    private let client: PostgresClient
    private var runTask: Task<Void, Never>?

    init(urlString: String) throws {
        let config = try Self.configuration(from: urlString)
        client = PostgresClient(configuration: config)
    }

    func start() {
        runTask = Task { [client] in await client.run() }
    }

    func shutdown() {
        runTask?.cancel()
    }

    // MARK: - Connection string

    static func configuration(from urlString: String) throws -> PostgresClient.Configuration {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              let host = comps.host, !host.isEmpty,
              let user = comps.user, !user.isEmpty
        else { throw DatabaseError.badURL("expected postgresql://user:password@host/database") }

        let database = comps.path.hasPrefix("/") ? String(comps.path.dropFirst()) : comps.path
        let sslmode = comps.queryItems?.first { $0.name == "sslmode" }?.value ?? "require"

        var tls: PostgresClient.Configuration.TLS = .disable
        if sslmode != "disable" {
            tls = .require(.makeClientConfiguration())
        }

        var config = PostgresClient.Configuration(
            host: host,
            port: comps.port ?? 5432,
            username: user,
            password: comps.password,
            database: database.isEmpty ? nil : database,
            tls: tls
        )
        // Neon's free tier is connection-shy; keep the pool small.
        config.options.minimumConnections = 0
        config.options.maximumConnections = 6
        return config
    }

    // MARK: - Schema

    func bootstrap() async throws {
        try await client.query("""
            create table if not exists nc_users (
                id uuid primary key default gen_random_uuid(),
                email text unique not null,
                name text not null,
                pin_hash text not null,
                pin_salt text not null,
                created_at timestamptz not null default now()
            )
            """)
        try await client.query("""
            create table if not exists nc_tasks (
                id uuid primary key default gen_random_uuid(),
                title text not null,
                status text not null default 'backlog',
                important boolean not null default false,
                assignee_id uuid references nc_users(id) on delete set null,
                position double precision not null default 0,
                created_by uuid references nc_users(id) on delete set null,
                created_at timestamptz not null default now(),
                updated_at timestamptz not null default now()
            )
            """)
        try await client.query("""
            create table if not exists nc_outreach (
                user_id uuid not null references nc_users(id) on delete cascade,
                day date not null default current_date,
                count integer not null default 0,
                primary key (user_id, day)
            )
            """)
    }

    // MARK: - Accounts

    private static func hash(pin: String, salt: String) -> String {
        let digest = SHA256.hash(data: Data((salt + pin).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeSalt() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    func signUp(email: String, name: String, pin: String) async throws -> BoardUser {
        let email = email.lowercased().trimmingCharacters(in: .whitespaces)
        let name = name.trimmingCharacters(in: .whitespaces)
        let existing = try await client.query("select id from nc_users where email = \(email)")
        for try await _ in existing.decode(UUID.self) { throw DatabaseError.emailTaken }

        let salt = Self.makeSalt()
        let hash = Self.hash(pin: pin, salt: salt)
        let rows = try await client.query("""
            insert into nc_users (email, name, pin_hash, pin_salt)
            values (\(email), \(name), \(hash), \(salt))
            returning id
            """)
        for try await id in rows.decode(UUID.self) {
            return BoardUser(id: id, email: email, name: name)
        }
        throw DatabaseError.notFound
    }

    func logIn(email: String, pin: String) async throws -> BoardUser {
        let email = email.lowercased().trimmingCharacters(in: .whitespaces)
        let rows = try await client.query("""
            select id, name, pin_hash, pin_salt from nc_users where email = \(email)
            """)
        for try await (id, name, hash, salt) in rows.decode((UUID, String, String, String).self) {
            guard Self.hash(pin: pin, salt: salt) == hash else { throw DatabaseError.badCredentials }
            return BoardUser(id: id, email: email, name: name)
        }
        throw DatabaseError.badCredentials
    }

    func user(id: UUID) async throws -> BoardUser? {
        let rows = try await client.query("select id, email, name from nc_users where id = \(id)")
        for try await (id, email, name) in rows.decode((UUID, String, String).self) {
            return BoardUser(id: id, email: email, name: name)
        }
        return nil
    }

    func users() async throws -> [BoardUser] {
        let rows = try await client.query("select id, email, name from nc_users order by name")
        var out: [BoardUser] = []
        for try await (id, email, name) in rows.decode((UUID, String, String).self) {
            out.append(BoardUser(id: id, email: email, name: name))
        }
        return out
    }

    // MARK: - Board

    func tasks() async throws -> [BoardTask] {
        let rows = try await client.query("""
            select id, title, status, important, assignee_id, position, created_at
            from nc_tasks
            order by important desc, position asc, created_at asc
            """)
        var out: [BoardTask] = []
        for try await (id, title, status, important, assignee, position, created) in
            rows.decode((UUID, String, String, Bool, UUID?, Double, Date).self) {
            out.append(BoardTask(id: id,
                                 title: title,
                                 status: TaskStatus(rawValue: status) ?? .backlog,
                                 important: important,
                                 assigneeID: assignee,
                                 position: position,
                                 createdAt: created))
        }
        return out
    }

    func addTask(title: String, status: TaskStatus, assignee: UUID?, createdBy: UUID) async throws {
        try await client.query("""
            insert into nc_tasks (title, status, assignee_id, position, created_by)
            values (\(title), \(status.rawValue), \(assignee),
                    (select coalesce(max(position), 0) + 1 from nc_tasks where status = \(status.rawValue)),
                    \(createdBy))
            """)
    }

    func move(_ id: UUID, to status: TaskStatus) async throws {
        try await client.query("""
            update nc_tasks
               set status = \(status.rawValue),
                   position = (select coalesce(max(position), 0) + 1 from nc_tasks where status = \(status.rawValue)),
                   updated_at = now()
             where id = \(id)
            """)
    }

    func setImportant(_ id: UUID, _ important: Bool) async throws {
        try await client.query("""
            update nc_tasks set important = \(important), updated_at = now() where id = \(id)
            """)
    }

    func assign(_ id: UUID, to user: UUID?) async throws {
        try await client.query("""
            update nc_tasks set assignee_id = \(user), updated_at = now() where id = \(id)
            """)
    }

    func rename(_ id: UUID, to title: String) async throws {
        try await client.query("""
            update nc_tasks set title = \(title), updated_at = now() where id = \(id)
            """)
    }

    func delete(_ id: UUID) async throws {
        try await client.query("delete from nc_tasks where id = \(id)")
    }

    // MARK: - Outreach counter (per person, per day)

    func outreachCount(for user: UUID) async throws -> Int {
        let rows = try await client.query("""
            select count from nc_outreach where user_id = \(user) and day = current_date
            """)
        for try await value in rows.decode(Int.self) { return value }
        return 0
    }

    @discardableResult
    func bumpOutreach(for user: UUID, by delta: Int) async throws -> Int {
        let rows = try await client.query("""
            insert into nc_outreach (user_id, day, count)
            values (\(user), current_date, \(max(0, delta)))
            on conflict (user_id, day)
            do update set count = greatest(0, nc_outreach.count + \(delta))
            returning count
            """)
        for try await value in rows.decode(Int.self) { return value }
        return 0
    }

    @discardableResult
    func resetOutreach(for user: UUID) async throws -> Int {
        try await client.query("""
            insert into nc_outreach (user_id, day, count) values (\(user), current_date, 0)
            on conflict (user_id, day) do update set count = 0
            """)
        return 0
    }

    /// Everyone's number for today — shown as the team total inside the panel.
    func teamOutreachToday() async throws -> [UUID: Int] {
        let rows = try await client.query("""
            select user_id, count from nc_outreach where day = current_date
            """)
        var out: [UUID: Int] = [:]
        for try await (id, count) in rows.decode((UUID, Int).self) { out[id] = count }
        return out
    }
}
