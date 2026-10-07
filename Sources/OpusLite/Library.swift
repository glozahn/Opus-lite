import AVFoundation
import Speech
import AppKit
import Observation

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

/// Interface language. "System" follows the macOS language list.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, es

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .en: "English"
        case .es: "Español"
        }
    }

    static var current: AppLanguage {
        guard let saved = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] as? [String],
              let first = saved.first else { return .system }
        return first.hasPrefix("es") ? .es : .en
    }

    /// Stored in the app's AppleLanguages default; takes effect on the next launch.
    func apply() {
        switch self {
        case .system: UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .en, .es: UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// App state: persistent library, processing queue and preferences.
@MainActor
@Observable
final class Library {
    var items: [LibraryItem] = []
    var filter: SidebarFilter = .all
    var selection: Set<UUID> = []
    var search = ""
    var sort: SortOrder = .newest { didSet { defaults.set(sort.rawValue, forKey: "sort") } }

    var locales: [Locale] = []
    var installedLocales: Set<String> = []

    // Preferences
    var engine: Engine = .speech { didSet { defaults.set(engine.rawValue, forKey: "engine") } }
    /// Transcription language; defaults to the system language.
    var localeID = Locale.current.identifier { didSet { defaults.set(localeID, forKey: "locale") } }
    var showTimestamps = true { didSet { defaults.set(showTimestamps, forKey: "timestamps") } }
    var autoTranscribe = true { didSet { defaults.set(autoTranscribe, forKey: "autoTranscribe") } }
    var exportFormat: ExportFormat = .txt { didSet { defaults.set(exportFormat.rawValue, forKey: "exportFormat") } }
    var appearance: Appearance = .system {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    private let defaults = UserDefaults.standard
    private var runner: Task<Void, Never>?
    private var currentJob: (id: UUID, task: Task<Void, Never>)?
    private var saveTask: Task<Void, Never>?

    private static let storeURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpusLite", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    init() {
        if let raw = defaults.string(forKey: "engine"), let v = Engine(rawValue: raw) { engine = v }
        if let v = defaults.string(forKey: "locale") { localeID = v }
        if defaults.object(forKey: "timestamps") != nil { showTimestamps = defaults.bool(forKey: "timestamps") }
        if defaults.object(forKey: "autoTranscribe") != nil { autoTranscribe = defaults.bool(forKey: "autoTranscribe") }
        if let raw = defaults.string(forKey: "exportFormat"), let v = ExportFormat(rawValue: raw) { exportFormat = v }
        if let raw = defaults.string(forKey: "sort"), let v = SortOrder(rawValue: raw) { sort = v }
        if let raw = defaults.string(forKey: "appearance"), let v = Appearance(rawValue: raw) { appearance = v }
        load()
        Task {
            await refreshInstalled()
            // Map the system locale (e.g. en_MX) to one the engine supports.
            if await Transcriber.supportedLocales().contains(where: { $0.identifier == localeID }) == false,
               let match = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeID)) {
                localeID = match.identifier
            }
            // Downloaded first, then by localized name.
            let installed = installedLocales
            locales = await Transcriber.supportedLocales().sorted { a, b in
                let ia = installed.contains(a.identifier), ib = installed.contains(b.identifier)
                if ia != ib { return ia }
                return localeName(a.identifier).localizedStandardCompare(localeName(b.identifier)) == .orderedAscending
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: - Queries

    var visibleItems: [LibraryItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let filtered = items.filter { item in
            guard filter.includes(item) else { return false }
            guard !query.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(query)
                || item.segments.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .newest: return filtered.sorted { $0.added > $1.added }
        case .oldest: return filtered.sorted { $0.added < $1.added }
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .duration: return filtered.sorted { $0.duration > $1.duration }
        }
    }

    func count(_ filter: SidebarFilter) -> Int {
        items.filter(filter.includes).count
    }

    var selectedItems: [LibraryItem] {
        items.filter { selection.contains($0.id) }
    }

    var selectedItem: LibraryItem? {
        selection.count == 1 ? items.first { $0.id == selection.first } : nil
    }

    func item(_ id: UUID) -> LibraryItem? {
        items.first { $0.id == id }
    }

    func binding(_ id: UUID) -> Int? {
        items.firstIndex { $0.id == id }
    }

    var locale: Locale { Locale(identifier: localeID) }

    /// Language name in the interface language.
    func localeName(_ id: String) -> String {
        let ui = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return ui.localizedString(forIdentifier: id).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? id
    }

    /// OCR languages from the chosen language, with English as a fallback.
    var ocrLanguages: [String] {
        let lang = locale.language.languageCode?.identifier ?? "es"
        let region = locale.region?.identifier ?? ""
        return [region.isEmpty ? lang : "\(lang)-\(region)", lang, "en-US"]
    }

    // MARK: - Import

    func add(_ urls: [URL]) {
        var files: [URL] = []
        for url in urls {
            if url.hasDirectoryPath,
               let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                files += e.compactMap { $0 as? URL }.filter { !$0.hasDirectoryPath }
            } else {
                files.append(url)
            }
        }
        files.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var added: [UUID] = []
        for (offset, url) in files.enumerated() {
            let path = url.standardizedFileURL.path
            if let i = items.firstIndex(where: { $0.path == path }) {
                items[i].trashed = nil
                added.append(items[i].id)
                continue
            }
            guard let kind = FileKind.detect(url) else { continue }
            // Stable order: WhatsApp names carry the date, so the last imported stays on top.
            var item = LibraryItem(path: path, added: Date().addingTimeInterval(Double(offset) * 0.001), kind: kind)
            item.pages = Media.pageCount(of: url, kind: kind)
            items.append(item)
            added.append(item.id)
            let id = item.id
            Task {
                let d = await Media.duration(of: url, kind: kind)
                if let i = binding(id) { items[i].duration = d }
                scheduleSave()
            }
        }
        guard !added.isEmpty else { return }
        if filter == .trash || filter == .favorites { filter = .all }
        selection = [added.last!]
        if autoTranscribe {
            enqueue(added.filter { item($0)?.status == .pending })
        }
        scheduleSave()
    }

    func importPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie, .pdf, .image]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = String(localized: "Audio, video, PDF or images")
        if panel.runModal() == .OK { add(panel.urls) }
    }

    // MARK: - Queue

    func transcribeSelection() {
        let targets = selectedItems.filter { !$0.status.isActive }
        if targets.isEmpty {
            enqueue(items.filter { $0.status == .pending && $0.trashed == nil }.map(\.id))
        } else {
            enqueue(targets.map(\.id))
        }
    }

    func enqueue(_ ids: [UUID]) {
        for id in ids {
            guard let i = binding(id), !items[i].status.isActive, items[i].fileExists else { continue }
            items[i].status = .queued
        }
        startRunner()
    }

    func cancel(_ id: UUID) {
        if currentJob?.id == id { currentJob?.task.cancel() }
        if let i = binding(id), items[i].status.isActive { items[i].status = items[i].segments.isEmpty ? .pending : .done }
    }

    func cancelAll() {
        for i in items.indices where items[i].status == .queued { items[i].status = .pending }
        if let job = currentJob { cancel(job.id) }
    }

    var isProcessing: Bool { items.contains { $0.status.isActive } }

    private func startRunner() {
        guard runner == nil else { return }
        runner = Task {
            while let next = items.first(where: { $0.status == .queued }) {
                let job = Task { await process(next.id) }
                currentJob = (next.id, job)
                await job.value
                currentJob = nil
            }
            runner = nil
            scheduleSave()
        }
    }

    private func process(_ id: UUID) async {
        guard let i = binding(id) else { return }
        items[i].status = .working(0)
        let previous = items[i].segments
        let snapshot = items[i]
        let engine = engine
        let localeID = localeID
        let start = Date()

        // Refresh the UI at most 4 times a second: if every partial result waited
        // for the main thread, the engine would run at the pace of the interface.
        let gate = Throttle(interval: 0.25)
        let partialGate = Throttle(interval: 0.25)
        let progress: @Sendable (Double) async -> Void = { [weak self] value in
            guard gate.allow() else { return }
            Task { @MainActor in
                guard let self, let i = self.binding(id), self.items[i].status.isActive else { return }
                self.items[i].status = .working(value)
            }
        }

        do {
            let segments: [Segment]
            if snapshot.kind.isDocument {
                segments = try await Media.recognizeText(in: snapshot, languages: ocrLanguages, progress: progress)
            } else {
                let audio = try await Media.playableAudio(for: snapshot)
                segments = try await Transcriber.run(
                    url: audio, duration: snapshot.duration, engine: engine, locale: Locale(identifier: localeID),
                    progress: progress,
                    partial: { [weak self] live in
                        guard partialGate.allow() else { return }
                        Task { @MainActor in
                            guard let self, let i = self.binding(id), self.items[i].status.isActive else { return }
                            self.items[i].segments = live
                        }
                    }
                )
            }
            try Task.checkCancellation()
            guard let i = binding(id) else { return }
            items[i].segments = segments
            items[i].status = .done
            items[i].elapsed = Date().timeIntervalSince(start)
            items[i].engine = snapshot.kind.isDocument ? nil : engine
            items[i].localeID = localeID
            items[i].modified = Date()
            if !snapshot.kind.isDocument { await refreshInstalled() }
        } catch {
            guard let i = binding(id) else { return }
            if Task.isCancelled || error is CancellationError {
                items[i].segments = previous
                items[i].status = previous.isEmpty ? .pending : .done
            } else {
                items[i].segments = previous
                items[i].status = .failed(Self.friendly(error))
            }
        }
        scheduleSave()
    }

    /// CoreAudio/AVFoundation errors rewritten into something readable.
    private static func friendly(_ error: Error) -> String {
        if error is TranscriptionError { return error.localizedDescription }
        let ns = error as NSError
        if ns.domain.contains("coreaudio") || ns.domain.contains("avfaudio") || ns.domain == NSOSStatusErrorDomain
            || ns.domain == AVFoundationErrorDomain {
            return String(localized: "Could not read the audio: the file is damaged or its format is not supported.")
        }
        return error.localizedDescription
    }

    // MARK: - Organize

    func toggleFavorite(_ id: UUID) {
        guard let i = binding(id) else { return }
        items[i].favorite.toggle()
        scheduleSave()
    }

    func trash(_ ids: Set<UUID>) {
        for id in ids {
            cancel(id)
            if let i = binding(id) { items[i].trashed = Date() }
        }
        selection.subtract(ids)
        scheduleSave()
    }

    func restore(_ ids: Set<UUID>) {
        for id in ids { if let i = binding(id) { items[i].trashed = nil } }
        scheduleSave()
    }

    /// Removes from the library. Only deletes files the app created (recordings and extracted audio).
    func removeForever(_ ids: Set<UUID>) {
        for id in ids {
            guard let item = item(id) else { continue }
            if item.path.hasPrefix(Recorder.folder.path) { try? FileManager.default.removeItem(at: item.url) }
            try? FileManager.default.removeItem(at: Media.cacheDir.appendingPathComponent(id.uuidString).appendingPathExtension("m4a"))
        }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        scheduleSave()
    }

    func emptyTrash() {
        removeForever(Set(items.filter { $0.trashed != nil }.map(\.id)))
    }

    /// Asks, then forgets every file and transcript. Originals are never touched; recordings
    /// made in Opus Lite are deleted only when the box is checked.
    func confirmClearHistory() {
        guard !items.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Clear the history?")
        alert.informativeText = String(localized: "This removes all \(items.count) files and their transcripts from Opus Lite. Your original files stay where they are. This can't be undone.")
        let box = NSButton(checkboxWithTitle: String(localized: "Also delete recordings made in Opus Lite"), target: nil, action: nil)
        box.state = .off
        alert.accessoryView = box
        alert.addButton(withTitle: String(localized: "Clear History"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clearHistory(deleteRecordings: box.state == .on)
    }

    func clearHistory(deleteRecordings: Bool) {
        cancelAll()
        let recordings = items.filter { $0.path.hasPrefix(Recorder.folder.path) }
        if deleteRecordings {
            for item in recordings { try? FileManager.default.removeItem(at: item.url) }
        }
        try? FileManager.default.removeItem(at: Media.cacheDir)
        try? FileManager.default.createDirectory(at: Media.cacheDir, withIntermediateDirectories: true)
        items.removeAll()
        selection.removeAll()
        search = ""
        saveNow()
    }

    /// Editing a paragraph merges its source segments into one with the new text.
    func edit(_ id: UUID, paragraph: Segment, sources: [UUID], text: String) {
        guard let i = binding(id) else { return }
        var segs = items[i].segments
        guard let first = segs.firstIndex(where: { $0.id == paragraph.id }) else { return }
        segs[first].text = text
        segs[first].end = paragraph.end
        let rest = Set(sources.dropFirst())
        segs.removeAll { rest.contains($0.id) }
        items[i].segments = segs
        items[i].modified = Date()
        scheduleSave()
    }

    func copyText(_ item: LibraryItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Exporter.text(item, timestamps: showTimestamps), forType: .string)
    }

    func refreshInstalled() async {
        installedLocales = await Transcriber.installedLocales()
    }

    func applyAppearance() {
        switch appearance {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let saved = try? JSONDecoder().decode([LibraryItem].self, from: data) else { return }
        items = saved.map { item in
            var item = item
            if item.status.isActive { item.status = item.segments.isEmpty ? .pending : .done }
            return item
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    func saveNow() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }
}

/// Lets through at most one call per interval.
final class Throttle: @unchecked Sendable {
    private let lock = NSLock()
    private let interval: TimeInterval
    private var last = Date.distantPast

    init(interval: TimeInterval) { self.interval = interval }

    func allow() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(last) >= interval else { return false }
        last = now
        return true
    }
}
