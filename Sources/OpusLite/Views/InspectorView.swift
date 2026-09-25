import SwiftUI

struct InspectorView: View {
    @Bindable var library: Library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Options").font(.headline)
                    Spacer()
                    SettingsLink {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Settings")
                }

                field("Engine") {
                    Picker("Engine", selection: $library.engine) {
                        ForEach(Engine.allCases) { engine in
                            Label(engine.title, systemImage: "cpu").tag(engine)
                        }
                    }
                    .labelsHidden()
                } note: {
                    Text("\(library.engine.detail) Processed on this Mac.")
                }

                field("Language") {
                    Picker("Language", selection: $library.localeID) {
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
                        Label("Model downloaded", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Downloads once, the first time.", systemImage: "arrow.down.circle")
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    switchRow("Timestamps", isOn: $library.showTimestamps)
                    switchRow("Transcribe on import", isOn: $library.autoTranscribe)
                }

                if let item = library.selectedItem, item.status == .done {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This File").font(.subheadline.weight(.semibold))
                        info("Engine", item.engine?.title ?? (item.kind.isDocument ? "OCR (Vision)" : "—"))
                        if let id = item.localeID { info("Language", library.localeName(id)) }
                        if let e = item.elapsed { info("Time", "\(e.formatted(.number.precision(.fractionLength(1)))) s") }
                        if item.duration > 0, let e = item.elapsed, e > 0 {
                            info("Speed", String(localized: "\(Int(item.duration / e))× real time"))
                        }
                        info("Words", "\(item.wordCount)")
                        info("Segments", "\(item.segments.count)")
                    }
                }
            }
            .padding(18)
        }
        .inspectorColumnWidth(min: 220, ideal: 250, max: 320)
    }

    private func field<C: View, N: View>(_ title: LocalizedStringKey, @ViewBuilder control: () -> C, @ViewBuilder note: () -> N) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            control()
            note()
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func switchRow(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func info(_ key: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
