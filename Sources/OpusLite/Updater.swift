import AppKit
import CryptoKit
import Observation

/// Checks GitHub Releases for a newer Opus Lite. One small HTTPS request, only when asked
/// or every few hours when automatic updates are on.
@MainActor
enum UpdateChecker {
    static let repository = "glozahn/Opus-lite"
    static let repositoryURL = URL(string: "https://github.com/\(repository)")!
    static let releasesURL = URL(string: "https://github.com/\(repository)/releases/latest")!
    static let issuesURL = URL(string: "https://github.com/\(repository)/issues")!

    struct Release {
        let version: String
        let page: URL
        let download: URL?
        let checksum: URL?
        let notes: String
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ value: String) -> [Int] {
            value.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: "-").first?
                .split(separator: ".").map { Int($0) ?? 0 } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The newest published release, or nil when GitHub says nothing useful.
    static func latest() async throws -> Release? {
        let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let urls = (json["assets"] as? [[String: Any]] ?? []).compactMap { $0["browser_download_url"] as? String }
        let dmgs = urls.filter { $0.hasSuffix(".dmg") }
        let download = (dmgs.first { $0.contains(architecture) } ?? dmgs.first).flatMap(URL.init(string:))
        let checksum = download.flatMap { dmg in urls.first { $0.hasSuffix(dmg.lastPathComponent + ".sha256") } }
            .flatMap(URL.init(string:))
        return Release(version: tag, page: page, download: download, checksum: checksum, notes: json["body"] as? String ?? "")
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}

/// Keeps Opus Lite up to date on its own: it downloads the disk image from GitHub Releases,
/// checks it, and swaps the app in place. Nothing is installed that is not signed by the
/// same developer as the copy already running, and notarized by Apple.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    struct Ready: Equatable {
        let version: String
        /// The new app, already verified, waiting next to the one in use.
        let app: URL
    }

    private(set) var ready: Ready?
    private(set) var working = false
    private(set) var failure: String?

    var automatic: Bool {
        get { UserDefaults.standard.object(forKey: "automaticUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "automaticUpdates") }
    }

    private var stagingFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpusLite/Updates", isDirectory: true)
    }

    /// Where the running app lives, when we are allowed to replace it.
    private var installedApp: URL? {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app",
              !url.path.contains("/AppTranslocation/"),
              !url.path.contains("/Volumes/"),
              FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path),
              FileManager.default.isWritableFile(atPath: url.path) else { return nil }
        return url
    }

    var canInstall: Bool { installedApp != nil }

    // MARK: Checking

    /// On launch and when the app comes back to the front: at most every six hours.
    func checkInBackground() {
        guard automatic, !working, ready == nil else { return }
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        guard Date().timeIntervalSince1970 - last > 21_600 else { return }
        Task { await check(userInitiated: false) }
    }

    /// *Check for Updates…*: installs a ready update right away, or looks for one and says what it found.
    func checkNow() {
        if ready != nil {
            install(relaunch: true)
            return
        }
        guard !working else { return }
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        working = true
        failure = nil
        defer { working = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        do {
            guard let release = try await UpdateChecker.latest() else {
                if userInitiated { alert(String(localized: "Could not check for updates"), String(localized: "Check your connection and try again.")) }
                return
            }
            guard UpdateChecker.isNewer(release.version, than: UpdateChecker.currentVersion) else {
                if userInitiated {
                    alert(String(localized: "Opus Lite is up to date"),
                          String(localized: "You have the latest version (\(UpdateChecker.currentVersion))."))
                }
                return
            }
            let version = release.version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            // Copies that cannot replace themselves (run from the disk image, or a read-only folder)
            // point to the download instead.
            guard canInstall, let download = release.download else {
                if userInitiated { offerDownload(release, version: version) }
                return
            }
            let app = try await fetchAndVerify(download, checksum: release.checksum, version: version)
            ready = Ready(version: version, app: app)
            if userInitiated { install(relaunch: true) }
        } catch {
            let message = (error as? UpdateError)?.message ?? error.localizedDescription
            failure = message
            if userInitiated {
                let alert = NSAlert()
                alert.messageText = String(localized: "Could not update")
                alert.informativeText = message
                alert.addButton(withTitle: String(localized: "OK"))
                alert.addButton(withTitle: String(localized: "Open Releases"))
                if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(UpdateChecker.releasesURL) }
            }
        }
    }

    private func offerDownload(_ release: UpdateChecker.Release, version: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Opus Lite \(version) is available")
        let notes = release.notes.split(separator: "\n").prefix(8).joined(separator: "\n")
        alert.informativeText = String(localized: "You have version \(UpdateChecker.currentVersion).")
            + (notes.isEmpty ? "" : "\n\n" + notes)
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Later"))
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.download ?? release.page) }
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    // MARK: Download and checks

    private func fetchAndVerify(_ download: URL, checksum: URL?, version: String) async throws -> URL {
        let session = URLSession(configuration: .ephemeral)
        let (file, response) = try await session.download(from: download)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }

        if let checksum, let expected = try? await session.data(from: checksum).0,
           let text = String(data: expected, encoding: .utf8)?.split(separator: " ").first {
            let digest = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))
            let actual = digest.map { String(format: "%02x", $0) }.joined()
            guard actual == text.lowercased() else { throw UpdateError.checksum }
        }

        let mount = stagingFolder.appendingPathComponent("mount-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard run("/usr/bin/hdiutil", ["attach", file.path, "-nobrowse", "-readonly", "-mountpoint", mount.path]) else {
            throw UpdateError.mount
        }
        defer {
            run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet"])
            try? FileManager.default.removeItem(at: mount)
        }

        guard let name = try FileManager.default.contentsOfDirectory(atPath: mount.path).first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.contents
        }
        let newApp = mount.appendingPathComponent(name)
        try verify(newApp)

        let staged = stagingFolder.appendingPathComponent("\(version)/\(name)")
        try? FileManager.default.removeItem(at: staged.deletingLastPathComponent())
        try FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", [newApp.path, staged.path]) else { throw UpdateError.copy }
        return staged
    }

    /// The update has to be signed by the same team as the running app, and notarized.
    private func verify(_ app: URL) throws {
        guard let team = Self.teamIdentifier(of: app), team == Self.teamIdentifier(of: Bundle.main.bundleURL) else {
            throw UpdateError.signature
        }
        var requirement: SecRequirement?
        let rule = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString
        guard SecRequirementCreateWithString(rule, [], &requirement) == errSecSuccess, let requirement else {
            throw UpdateError.signature
        }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw UpdateError.signature }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw UpdateError.signature }
        // Gatekeeper's own verdict, which also covers notarization.
        guard run("/usr/sbin/spctl", ["--assess", "--type", "exec", app.path]) else { throw UpdateError.notarization }
    }

    private static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary["teamid"] as? String
    }

    // MARK: Installing

    /// Swaps the app once this process is gone. Called on quit, or right away when the user asks.
    func install(relaunch: Bool) {
        guard let ready, let current = installedApp else { return }
        let script = stagingFolder.appendingPathComponent("install-\(ready.version).sh")
        let body = """
        #!/bin/sh
        while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf \(quote(current.path + ".old"))
        /bin/mv \(quote(current.path)) \(quote(current.path + ".old")) || exit 1
        /usr/bin/ditto \(quote(ready.app.path)) \(quote(current.path)) || { /bin/mv \(quote(current.path + ".old")) \(quote(current.path)); exit 1; }
        /usr/bin/xattr -dr com.apple.quarantine \(quote(current.path))
        /bin/rm -rf \(quote(current.path + ".old")) \(quote(ready.app.deletingLastPathComponent().path))
        \(relaunch ? "/usr/bin/open " + quote(current.path) : "")
        """
        UserDefaults.standard.set(UpdateChecker.currentVersion, forKey: "updatedFromVersion")
        do {
            try FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
            try body.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = [script.path]
            try task.run()
        } catch {
            failure = error.localizedDescription
            return
        }
        self.ready = nil
        if relaunch { NSApp.terminate(nil) }
    }

    /// Called when the app is quitting anyway: the update lands without interrupting anyone.
    func installOnQuit() {
        guard ready != nil else { return }
        install(relaunch: false)
    }

    /// True once, on the first launch after an update installed.
    func consumeJustUpdated() -> Bool {
        let key = "updatedFromVersion"
        guard let previous = UserDefaults.standard.string(forKey: key) else { return false }
        UserDefaults.standard.removeObject(forKey: key)
        return previous != UpdateChecker.currentVersion
    }

    private func quote(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    enum UpdateError: Error {
        case download, checksum, mount, contents, copy, signature, notarization

        var message: String {
            switch self {
            case .download: String(localized: "The update could not be downloaded.")
            case .checksum: String(localized: "The download does not match its checksum.")
            case .mount, .contents, .copy: String(localized: "The downloaded disk image could not be opened.")
            case .signature: String(localized: "The update is not signed by the same developer.")
            case .notarization: String(localized: "The update is not notarized by Apple.")
            }
        }
    }
}
