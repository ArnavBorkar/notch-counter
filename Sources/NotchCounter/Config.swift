import Foundation

/// Where the Postgres URL comes from, in order:
///   1. `NOTCH_DB_URL` in the environment
///   2. `~/.config/notch-counter/config.json`  → { "databaseURL": "postgresql://..." }
///   3. the login keychain (saved after you paste it into the setup screen)
enum Config {
    private static let keychainAccount = "database-url"

    static var configFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/notch-counter/config.json")
    }

    static func databaseURL() -> String? {
        if let env = ProcessInfo.processInfo.environment["NOTCH_DB_URL"], !env.isEmpty {
            return env
        }
        if let data = try? Data(contentsOf: configFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let url = json["databaseURL"] as? String, !url.isEmpty {
            return url
        }
        return Keychain.string(for: keychainAccount)
    }

    /// The day the clock started. Optional `"countingSince": "2026-08-15"` in
    /// config.json overrides it; otherwise it's the most recent 15 August, so the
    /// number never goes negative.
    static func countingSince() -> Date {
        let calendar = Calendar.current
        if let data = try? Data(contentsOf: configFileURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = json["countingSince"] as? String {
            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd"
            parser.timeZone = .current
            if let date = parser.date(from: raw) { return calendar.startOfDay(for: date) }
        }

        let now = Date()
        var components = calendar.dateComponents([.year], from: now)
        components.month = 8
        components.day = 15
        let thisYear = calendar.date(from: components) ?? now
        if thisYear <= now { return calendar.startOfDay(for: thisYear) }
        components.year = (components.year ?? 2026) - 1
        return calendar.startOfDay(for: calendar.date(from: components) ?? now)
    }

    static func save(databaseURL: String) {
        Keychain.set(databaseURL, for: keychainAccount)
    }

    static func clearSavedDatabaseURL() {
        Keychain.remove(keychainAccount)
    }
}
