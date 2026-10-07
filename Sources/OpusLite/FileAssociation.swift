import AppKit
import Observation
import UniformTypeIdentifiers

/// Which app opens WhatsApp voice notes, and making Opus Lite that app.
/// macOS maps .opus, .ogg and .oga to the same type (org.xiph.ogg-audio).
@MainActor
@Observable
final class FileAssociation {
    private(set) var isDefault = false
    private(set) var currentName: String?
    var error: String?

    static let voiceNoteType = UTType(filenameExtension: "opus") ?? UTType("org.xiph.ogg-audio") ?? .audio

    init() {
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let url = NSWorkspace.shared.urlForApplication(toOpen: Self.voiceNoteType)
        isDefault = url.flatMap { Bundle(url: $0)?.bundleIdentifier } == Bundle.main.bundleIdentifier
        currentName = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }

    func makeDefault() {
        error = nil
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: Self.voiceNoteType) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.error = String(localized: "Could not set the default app: \(error.localizedDescription)")
                }
                self?.refresh()
            }
        }
    }
}
