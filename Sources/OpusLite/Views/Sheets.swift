import SwiftUI

struct ExportSheet: View {
    @Bindable var library: Library
    @Environment(\.dismiss) private var dismiss
    @State private var timestamps = true

    private var items: [LibraryItem] {
        library.selectedItems.filter { !$0.segments.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(items.count > 1 ? String(localized: "Export \(items.count) Transcripts") : String(localized: "Export Transcript"))
                .font(.headline)

            Form {
                Picker("Format", selection: $library.exportFormat) {
                    ForEach(ExportFormat.allCases) { f in
                        Text("\(f.title) — \(f.detail)").tag(f)
                    }
                }
                Toggle("Include timestamps", isOn: $timestamps)
                    .disabled(library.exportFormat.isSubtitle)
            }
            .formStyle(.columns)

            if library.exportFormat.isSubtitle, items.contains(where: { $0.kind.isDocument }) {
                Label("Documents have no timings; they are exported anyway.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save…") {
                    dismiss()
                    let format = library.exportFormat
                    let ts = timestamps
                    let targets = items
                    DispatchQueue.main.async {
                        if targets.count == 1 {
                            Exporter.save(targets[0], format: format, timestamps: ts)
                        } else {
                            Exporter.saveAll(targets, format: format, timestamps: ts)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(items.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .onAppear { timestamps = library.showTimestamps }
    }
}

struct RecordSheet: View {
    @Bindable var library: Library
    @State private var recorder = Recorder()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Record voice note").font(.headline)

            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(recorder.isRecording ? Color.red.opacity(0.8) : Color.secondary.opacity(0.3))
                        .frame(width: 4, height: max(4, CGFloat(level) * 60))
                }
            }
            .frame(height: 64)
            .animation(.linear(duration: 0.06), value: recorder.levels)

            Text(recorder.elapsed.clock)
                .font(.system(size: 34, weight: .light).monospacedDigit())

            if let error = recorder.error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Discard", role: .destructive) {
                    recorder.discard()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    if let url = recorder.stop() { library.add([url]) }
                    dismiss()
                } label: {
                    Label("Stop and Transcribe", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .disabled(!recorder.isRecording)
            }
        }
        .padding(26)
        .frame(width: 380)
        .task { await recorder.start() }
    }
}
