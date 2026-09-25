import AVFoundation
import Speech
import SwiftUI

struct SettingsView: View {
    @Bindable var library: Library

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings(library: library) }
            Tab("Modelos", systemImage: "cpu") { ModelSettings(library: library) }
            Tab("Privacidad", systemImage: "lock") { PrivacySettings() }
            Tab("Atajos", systemImage: "keyboard") { ShortcutSettings() }
            Tab("Acerca de", systemImage: "info.circle") { AboutSettings(library: library) }
        }
        .frame(width: 540, height: 400)
    }
}

private struct GeneralSettings: View {
    @Bindable var library: Library

    var body: some View {
        Form {
            Picker("Apariencia", selection: $library.appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Toggle("Transcribir automáticamente al importar", isOn: $library.autoTranscribe)
            Toggle("Mostrar marcas de tiempo", isOn: $library.showTimestamps)
            Picker("Formato de exportación", selection: $library.exportFormat) {
                ForEach(ExportFormat.allCases) { Text("\($0.title) — \($0.detail)").tag($0) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelSettings: View {
    @Bindable var library: Library
    @State private var downloading: [String: Double] = [:]
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Picker("Motor predeterminado", selection: $library.engine) {
                    ForEach(Engine.allCases) { Text($0.title).tag($0) }
                }
                Text("Los modelos son del sistema: no ocupan espacio en la app y funcionan sin internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Idiomas") {
                ForEach(library.locales, id: \.identifier) { loc in
                    HStack {
                        Text(library.localeName(loc.identifier))
                        Spacer()
                        if library.installedLocales.contains(loc.identifier) {
                            Label("Descargado", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.callout)
                        } else if let p = downloading[loc.identifier] {
                            ProgressView(value: p).frame(width: 90)
                            Text(p, format: .percent.precision(.fractionLength(0)))
                                .font(.callout.monospacedDigit())
                                .frame(width: 40)
                        } else {
                            Button("Descargar") { download(loc) }
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
    @State private var speech = SFSpeechRecognizer.authorizationStatus()
    @State private var mic = AVAudioApplication.shared.recordPermission

    var body: some View {
        Form {
            Section {
                Label("Todo se procesa en este Mac", systemImage: "lock.shield.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Opus Lite no envía audio, texto ni estadísticas a ningún servidor. La transcripción usa los modelos de voz de macOS y el OCR usa Vision, ambos locales.")
                    .foregroundStyle(.secondary)
            }
            Section("Permisos") {
                row("Reconocimiento de voz", granted: speech == .authorized,
                    note: "Solo lo usa el motor SFSpeech clásico.")
                row("Micrófono", granted: mic == .granted, note: "Para grabar notas de voz.")
                Button("Abrir Ajustes de privacidad…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
                }
            }
            Section("Datos") {
                Button("Mostrar carpeta de la biblioteca") {
                    NSWorkspace.shared.open(Recorder.folder.deletingLastPathComponent())
                }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ title: String, granted: Bool, note: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(title)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(granted ? "Permitido" : "Sin decidir o denegado")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.callout)
        }
    }
}

private struct ShortcutSettings: View {
    private let shortcuts: [(String, String)] = [
        ("Importar archivos", "⌘O"),
        ("Grabar nota de voz", "⇧⌘N"),
        ("Transcribir selección", "⌘R"),
        ("Cancelar", "⌘."),
        ("Exportar", "⌘E"),
        ("Copiar texto", "⇧⌘C"),
        ("Reproducir / pausa", "⌥ Espacio"),
        ("Buscar", "⌘F"),
        ("Mostrar opciones", "⌥⌘I"),
        ("Mover a la papelera", "⌫"),
    ]

    var body: some View {
        Form {
            ForEach(shortcuts, id: \.0) { name, keys in
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
            Text("Versión \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                .foregroundStyle(.secondary)
            Text("Audio, vídeo y documentos a texto. Nativo, ligero y privado.")
                .multilineTextAlignment(.center)
            HStack(spacing: 18) {
                stat("\(library.items.count)", "archivos")
                stat("\(library.items.reduce(0) { $0 + $1.wordCount })", "palabras")
                stat(library.items.reduce(0) { $0 + $1.duration }.clock, "de audio")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack {
            Text(value).font(.title3.monospacedDigit().weight(.semibold))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
