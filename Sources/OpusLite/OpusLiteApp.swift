import SwiftUI

/// Recibe todos los archivos de "Abrir con" (onOpenURL solo entrega el primero).
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpen: (([URL]) -> Void)?
    private var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpen { onOpen(urls) } else { pending += urls }
    }

    func attach(_ handler: @escaping ([URL]) -> Void) {
        onOpen = handler
        if !pending.isEmpty { handler(pending); pending = [] }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct OpusLiteApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var library = Library()
    @State private var player = Player()
    @State private var showInspector = true
    @State private var showExport = false
    @State private var showRecorder = false

    var body: some Scene {
        Window("Opus Lite", id: "main") {
            RootView(
                library: library, player: player,
                showInspector: $showInspector, showExport: $showExport, showRecorder: $showRecorder
            )
            .frame(minWidth: 1240, minHeight: 660)
            .onAppear {
                library.applyAppearance()
                delegate.attach { library.add($0) }
                restoreWindowFrame()
            }
        }
        .defaultSize(width: 1380, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Importar…") { library.importPanel() }
                    .keyboardShortcut("o")
                Button("Grabar nota de voz…") { showRecorder = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Buscar") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                    .keyboardShortcut("f")
            }
            CommandGroup(after: .importExport) {
                Button("Exportar…") { showExport = true }
                    .keyboardShortcut("e")
                    .disabled(!library.selectedItems.contains { !$0.segments.isEmpty })
            }
            CommandMenu("Transcripción") {
                Button("Transcribir") { library.transcribeSelection() }
                    .keyboardShortcut("r")
                Button("Detener") { library.cancelAll() }
                    .keyboardShortcut(".")
                    .disabled(!library.isProcessing)
                Divider()
                Button("Copiar texto") { library.selectedItem.map(library.copyText) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(library.selectedItem?.segments.isEmpty ?? true)
                Button("Reproducir / pausa") { player.toggle() }
                    .keyboardShortcut(.space, modifiers: .option)
                    .disabled(player.duration == 0)
                Divider()
                Button("Mover a la papelera") { library.trash(library.selection) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(library.selection.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button(showInspector ? "Ocultar opciones" : "Mostrar opciones") { showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView(library: library)
        }
    }

    /// SwiftUI abre la ventana al tamaño mínimo y no recuerda el último: se guarda con autosave propio.
    private func restoreWindowFrame() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) else { return }
            if !window.setFrameUsingName("OpusLiteMain"), let screen = window.screen?.visibleFrame {
                let size = CGSize(width: min(1400, screen.width - 40), height: min(840, screen.height - 40))
                let origin = CGPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
                window.setFrame(CGRect(origin: origin, size: size), display: true, animate: false)
            }
            window.setFrameAutosaveName("OpusLiteMain")
        }
    }
}
