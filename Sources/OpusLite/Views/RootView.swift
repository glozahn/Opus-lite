import SwiftUI

struct RootView: View {
    @Bindable var library: Library
    @Bindable var player: Player
    let association: FileAssociation
    @Binding var showInspector: Bool
    @Binding var showExport: Bool
    @Binding var showRecorder: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(library: library)
        } content: {
            FileListView(library: library)
        } detail: {
            DetailView(library: library, player: player, association: association, showExport: $showExport)
        }
        .inspector(isPresented: $showInspector) {
            InspectorView(library: library)
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showExport) { ExportSheet(library: library) }
        .sheet(isPresented: $showRecorder) { RecordSheet(library: library) }
        .navigationTitle("Opus Lite")
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Import", systemImage: "plus") { library.importPanel() }
                .labelStyle(.titleAndIcon)
                .help("Import files (⌘O)")
            Button("Record", systemImage: "mic") { showRecorder = true }
                .labelStyle(.titleAndIcon)
                .help("Record voice note (⇧⌘N)")
        }
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 6) {
                Image(systemName: isLight ? "sun.max.fill" : "moon.fill")
                    .foregroundStyle(isLight ? .orange : .secondary)
                    .frame(width: 16)
                Toggle("Light mode", isOn: Binding(
                    get: { isLight },
                    set: { library.appearance = $0 ? .light : .dark }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            .padding(.horizontal, 4)
            .help("Light / dark mode")
        }
        ToolbarItem(placement: .primaryAction) {
            if library.isProcessing {
                Button("Stop", systemImage: "stop.fill") { library.cancelAll() }
                    .labelStyle(.titleAndIcon)
                    .help("Stop the queue (⌘.)")
            } else {
                Button("Transcribe", systemImage: "waveform") { library.transcribeSelection() }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canTranscribe)
                    .help("Transcribe selection (⌘R)")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Options", systemImage: "sidebar.right") { showInspector.toggle() }
                .help("Show options (⌥⌘I)")
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var isLight: Bool {
        switch library.appearance {
        case .light: true
        case .dark: false
        case .system: colorScheme == .light
        }
    }

    private var canTranscribe: Bool {
        !library.selectedItems.isEmpty || library.items.contains { $0.status == .pending && $0.trashed == nil }
    }
}
