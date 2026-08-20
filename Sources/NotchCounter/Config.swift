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

    static func save(databaseURL: String) {
        Keychain.set(databaseURL, for: keychainAccount)
    }

    static func clearSavedDatabaseURL() {
        Keychain.remove(keychainAccount)
    }
}
