import Foundation

struct AppRelease: Equatable, Sendable {
    let version: String          // "2.1.0"
    let tag: String              // "v2.1.0"
    let notes: String
    let download: URL
}

enum UpdateError: LocalizedError {
    case noAsset, badArchive, notTrusted

    var errorDescription: String? {
        switch self {
        case .noAsset:    return "That release has no NotchCounter.zip attached."
        case .badArchive: return "The download didn't contain the app."
        case .notTrusted: return "The download wasn't served from the project's GitHub releases."
        }
    }
}

/// Checks the project's GitHub releases and swaps the bundle in place.
enum Updater {
    static let repo = "ArnavBorkar/notch-counter"
    private static let assetName = "NotchCounter.zip"

    /// The last tag we installed. Guards against a release whose bundle carries a
    /// different version than its tag — without this the app would install it,
    /// come back still looking older, and offer the same update forever.
    private static let installedTagKey = "update.installedTag"

    static var installedTag: String? {
        get { UserDefaults.standard.string(forKey: installedTagKey) }
        set { UserDefaults.standard.set(newValue, forKey: installedTagKey) }
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Returns the release only when it's actually newer than what's running.
    static func check() async throws -> AppRelease? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchCounter/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String
        else { return nil }

        guard tag != installedTag else { return nil }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(version, than: currentVersion) else { return nil }

        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let asset = assets.first(where: { $0["name"] as? String == assetName }),
              let urlString = asset["browser_download_url"] as? String,
              let url = URL(string: urlString)
        else { throw UpdateError.noAsset }

        // only ever pull from this project's release host
        guard let host = url.host, host == "github.com" || host.hasSuffix(".githubusercontent.com"),
              url.path.contains(repo)
        else { throw UpdateError.notTrusted }

        return AppRelease(version: version,
                          tag: tag,
                          notes: (json["body"] as? String) ?? "",
                          download: url)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    /// Downloads the release, unpacks it, then hands off to a script that waits
    /// for this process to exit before replacing the bundle and relaunching.
    static func install(_ release: AppRelease) async throws {
        let (downloaded, response) = try await URLSession.shared.download(from: release.download)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.badArchive
        }

        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notch-update-\(release.version)")
        try? FileManager.default.removeItem(at: work)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let zip = work.appendingPathComponent(assetName)
        try FileManager.default.moveItem(at: downloaded, to: zip)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()

        let unpacked = work.appendingPathComponent("Notch Counter.app")
        guard FileManager.default.fileExists(
            atPath: unpacked.appendingPathComponent("Contents/MacOS/NotchCounter").path)
        else { throw UpdateError.badArchive }

        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app" else { throw UpdateError.badArchive }

        // Replace ourselves only once we're gone, then come back up.
        let script = """
            while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done
            rm -rf "\(target.path)"
            /usr/bin/ditto "\(unpacked.path)" "\(target.path)"
            /usr/bin/xattr -dr com.apple.quarantine "\(target.path)"
            rm -rf "\(work.path)"
            /usr/bin/open "\(target.path)"
            """
        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/sh")
        swap.arguments = ["-c", script]
        try swap.run()
    }
}
