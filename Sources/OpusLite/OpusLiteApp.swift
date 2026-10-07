import SwiftUI

/// Receives every file from "Open With" (onOpenURL only delivers the first).
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Updater.shared.checkInBackground() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated { Updater.shared.checkInBackground() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Updater.shared.installOnQuit() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct OpusLiteApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var library = Library()
    @State private var player = Player()
    @State private var association = FileAssociation()
    @State private var showInspector = true
    @State private var showExport = false
    @State private var showRecorder = false

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("Opus Lite", id: "main") {
            RootView(
                library: library, player: player, association: association,
                showInspector: $showInspector, showExport: $showExport, showRecorder: $showRecorder
            )
            .frame(minWidth: 1240, minHeight: 660)
            .onAppear {
                library.applyAppearance()
                delegate.attach { library.add($0) }
                restoreWindowFrame()
                if Updater.shared.consumeJustUpdated() { openWindow(id: "changelog") }
            }
        }
        .defaultSize(width: 1380, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkNow() }
            }
            CommandGroup(replacing: .help) {
                Button("What's New") { openWindow(id: "changelog") }
                Divider()
                Link("Opus Lite on GitHub", destination: UpdateChecker.repositoryURL)
                Link("Leave a Star on GitHub", destination: UpdateChecker.repositoryURL)
                Link("Report an Issue", destination: UpdateChecker.issuesURL)
            }
            CommandGroup(replacing: .newItem) {
                Button("Import…") { library.importPanel() }
                    .keyboardShortcut("o")
                Button("Record Voice Note…") { showRecorder = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Search") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                    .keyboardShortcut("f")
            }
            CommandGroup(after: .importExport) {
                Button("Export…") { showExport = true }
                    .keyboardShortcut("e")
                    .disabled(!library.selectedItems.contains { !$0.segments.isEmpty })
            }
            CommandMenu("Transcript") {
                Button("Transcribe") { library.transcribeSelection() }
                    .keyboardShortcut("r")
                Button("Stop") { library.cancelAll() }
                    .keyboardShortcut(".")
                    .disabled(!library.isProcessing)
                Divider()
                Button("Copy Text") { library.selectedItem.map(library.copyText) }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(library.selectedItem?.segments.isEmpty ?? true)
                Button("Play / Pause") { player.toggle() }
                    .keyboardShortcut(.space, modifiers: .option)
                    .disabled(player.duration == 0)
                Divider()
                Button("Move to Trash") { library.trash(library.selection) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(library.selection.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button(showInspector ? String(localized: "Hide Options") : String(localized: "Show Options")) { showInspector.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView(library: library, association: association)
        }

        Window("What's New", id: "changelog") {
            ChangelogView()
        }
        .defaultSize(width: 620, height: 640)
    }

    /// SwiftUI opens the window at its minimum size and forgets the last one, so autosave it ourselves.
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
