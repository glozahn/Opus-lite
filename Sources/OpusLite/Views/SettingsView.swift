import AVFoundation
import Speech
import SwiftUI

struct SettingsView: View {
    @Bindable var library: Library
    let association: FileAssociation

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings(library: library, association: association) }
            Tab("Models", systemImage: "cpu") { ModelSettings(library: library) }
            Tab("Privacy", systemImage: "lock") { PrivacySettings(library: library) }
            Tab("Shortcuts", systemImage: "keyboard") { ShortcutSettings() }
            Tab("About", systemImage: "info.circle") { AboutSettings(library: library) }
        }
        .frame(width: 540, height: 520)
    }
}

private struct GeneralSettings: View {
    @Bindable var library: Library
    let association: FileAssociation

    var body: some View {
        Form {
            Picker("Appearance", selection: $library.appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            LanguagePicker()
            Toggle("Transcribe automatically on import", isOn: $library.autoTranscribe)
            Toggle("Show timestamps", isOn: $library.showTimestamps)
            Picker("Export format", selection: $library.exportFormat) {
                ForEach(ExportFormat.allCases) { Text("\($0.title) — \($0.detail)").tag($0) }
            }
            Section("Updates") {
                Toggle("Update automatically", isOn: Binding(
                    get: { Updater.shared.automatic },
                    set: { Updater.shared.automatic = $0 }
                ))
                HStack {
                    Text("Version \(UpdateChecker.currentVersion)").foregroundStyle(.secondary)
                    Spacer()
                    if Updater.shared.working { ProgressView().controlSize(.small) }
                    Button("Check for Updates…") { Updater.shared.checkNow() }
                        .disabled(Updater.shared.working)
                }
            }
            Section("Voice notes") {
                HStack {
                    Image(systemName: association.isDefault ? "checkmark.circle.fill" : "doc.badge.gearshape")
                        .foregroundStyle(association.isDefault ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(association.isDefault ? "Opus Lite opens your .opus files" : "App for .opus files")
                        if !association.isDefault {
                            Text("Now: \(association.currentName ?? String(localized: "no app"))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !association.isDefault {
                        Button("Make Default") { association.makeDefault() }
                    }
                }
                if let error = association.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Interface language: System follows macOS; a change applies after relaunching.
private struct LanguagePicker: View {
    @State private var language = AppLanguage.current
    @State private var initial = AppLanguage.current

    var body: some View {
        Picker("Language", selection: $language) {
            ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
        }
        .onChange(of: language) { _, value in value.apply() }
        if language != initial {
            HStack {
                Text("Restart Opus Lite to change the language.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Restart Now") { relaunch() }
            }
        }
    }

    private func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

private struct ModelSettings: View {
    @Bindable var library: Library
    @State private var downloading: [String: Double] = [:]
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Picker("Default engine", selection: $library.engine) {
                    ForEach(Engine.allCases) { Text($0.title).tag($0) }
                }
                Text("Models belong to the system: they take no space in the app and work offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Languages") {
                ForEach(library.locales, id: \.identifier) { loc in
                    HStack {
                        Text(library.localeName(loc.identifier))
                        Spacer()
                        if library.installedLocales.contains(loc.identifier) {
                            Label("Downloaded", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                        } else if let p = downloading[loc.identifier] {
                            ProgressView(value: p).frame(width: 90)
                            Text(p, format: .percent.precision(.fractionLength(0)))
                                .font(.callout.monospacedDigit())
                                .frame(width: 40)
                        } else {
                            Button("Download") { download(loc) }
                                .controlSize(.small)
                        }
                    }
                }
            }
            if let error {
                Text(error).foregroundStyle(.red).font(.callout)
            }
        }
        .formStyle(.grouped)
        .task { await library.refreshInstalled() }
    }

    private func download(_ locale: Locale) {
        let id = locale.identifier
        downloading[id] = 0
        Task {
            do {
                try await Transcriber.installModel(for: locale) { p in
                    await MainActor.run { downloading[id] = p }
                }
                await library.refreshInstalled()
            } catch {
                self.error = error.localizedDescription
            }
            downloading[id] = nil
        }
    }
}

private struct PrivacySettings: View {
    let library: Library
    @State private var speech = SFSpeechRecognizer.authorizationStatus()
    @State private var mic = AVAudioApplication.shared.recordPermission

    var body: some View {
        Form {
            Section {
                Label("Everything is processed on this Mac", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Opus Lite sends no audio, text or analytics to any server. Transcription uses the macOS speech models and OCR uses Vision, both on device.")
                    .foregroundStyle(.secondary)
            }
            Section("Permissions") {
                row("Speech Recognition", granted: speech == .authorized,
                    note: String(localized: "Only used by the classic SFSpeech engine."))
                row("Microphone", granted: mic == .granted, note: String(localized: "To record voice notes."))
                Button("Open Privacy Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }
            }
            Section("Data") {
                Button("Show Library Folder") {
                    NSWorkspace.shared.open(Recorder.folder.deletingLastPathComponent())
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("History")
                        Text("\(library.items.count) files and their transcripts")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear History…", role: .destructive) { library.confirmClearHistory() }
                        .disabled(library.items.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ title: LocalizedStringKey, granted: Bool, note: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(granted ? String(localized: "Allowed") : String(localized: "Not decided or denied"))
                .foregroundStyle(granted ? .green : .secondary)
                .font(.callout)
        }
    }
}

private struct ShortcutSettings: View {
    private let shortcuts: [(LocalizedStringKey, String)] = [
        ("Import files", "⌘O"),
        ("Record voice note", "⇧⌘N"),
        ("Transcribe selection", "⌘R"),
        ("Cancel", "⌘."),
        ("Export", "⌘E"),
        ("Copy Text", "⇧⌘C"),
        ("Play / Pause", "⌥ Space"),
        ("Search", "⌘F"),
        ("Show Options", "⌥⌘I"),
        ("Move to Trash", "⌘⌫"),
    ]

    var body: some View {
        Form {
            ForEach(shortcuts, id: \.1) { name, keys in
                HStack {
                    Text(name)
                    Spacer()
                    Text(keys)
                        .font(.callout.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutSettings: View {
    let library: Library

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text("Opus Lite").font(.title2.weight(.semibold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                .foregroundStyle(.secondary)
            Text("Audio, video and documents to text. Native, light and private.")
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                stat("\(library.items.count)", "files")
                stat("\(library.items.reduce(0) { $0 + $1.wordCount })", "words")
                stat(library.items.reduce(0) { $0 + $1.duration }.clock, "of audio")
            }
            .padding(.top, 6)
            Link(destination: UpdateChecker.repositoryURL) {
                Label("Visit GitHub and leave a star", systemImage: "star.fill")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.top, 6)
            Button("Check for Updates…") { Updater.shared.checkNow() }
                .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack {
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
