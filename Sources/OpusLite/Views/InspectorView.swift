import SwiftUI

struct InspectorView: View {
    @Bindable var library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Opciones").font(.headline)
                    Spacer()
                    SettingsLink {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Ajustes")
                }

                field("Motor") {
                    Picker("Motor", selection: $library.engine) {
                        ForEach(Engine.allCases) { engine in
                            Label(engine.title, systemImage: "cpu").tag(engine)
                        }
                    }
                    .labelsHidden()
                } note: {
                    Text("\(library.engine.detail) Procesamiento en este Mac.")
                }

                field("Idioma") {
                    Picker("Idioma", selection: $library.localeID) {
                        if library.locales.isEmpty {
                            Text(library.localeName(library.localeID)).tag(library.localeID)
                        }
                        ForEach(library.locales, id: \.identifier) { loc in
                            Text(library.localeName(loc.identifier)).tag(loc.identifier)
                        }
                    }
                    .labelsHidden()
                } note: {
                    if library.installedLocales.contains(library.localeID) {
                        Label("Modelo descargado", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Se descargará la primera vez (una sola vez).", systemImage: "arrow.down.circle")
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    switchRow("Marcas de tiempo", isOn: $library.showTimestamps)
                    switchRow("Transcribir al importar", isOn: $library.autoTranscribe)
                }

                if let item = library.selectedItem, item.status == .done {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Este archivo").font(.subheadline.weight(.semibold))
                        info("Motor", item.engine?.title ?? (item.kind.isDocument ? "OCR (Vision)" : "—"))
                        if let id = item.localeID { info("Idioma", library.localeName(id)) }
                        if let e = item.elapsed { info("Tiempo", "\(e.formatted(.number.precision(.fractionLength(1)))) s") }
                        if item.duration > 0, let e = item.elapsed, e > 0 {
                            info("Velocidad", "\(Int(item.duration / e))× tiempo real")
                        }
                        info("Palabras", "\(item.wordCount)")
                        info("Tramos", "\(item.segments.count)")
                    }
                }
            }
            .padding(18)
        }
        .inspectorColumnWidth(min: 220, ideal: 250, max: 320)
    }

    private func field<C: View, N: View>(_ title: String, @ViewBuilder control: () -> C, @ViewBuilder note: () -> N) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            control()
            note()
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func info(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
