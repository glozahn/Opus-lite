import SwiftUI

struct SidebarView: View {
    @Bindable var library: Library

    var body: some View {
        List(selection: Binding(get: { library.filter }, set: { if let f = $0 { library.filter = f } })) {
            Section("Library") {
                ForEach(SidebarFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.icon)
                        .badge(library.count(filter))
                        .tag(filter)
                        .dropDestination(for: URL.self) { urls, _ in
                            guard filter == .all || filter == .recent else { return false }
                            library.add(urls)
                            return true
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
            if let ready = Updater.shared.ready {
                Button { Updater.shared.install(relaunch: true) } label: {
                    Label("Update to \(ready.version)", systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Restarts Opus Lite into the new version. Otherwise it installs when you quit.")
            }
            Link(destination: UpdateChecker.repositoryURL) {
                Label("Star on GitHub", systemImage: "star.fill")
                    .font(.callout)
            }
            .foregroundStyle(.secondary)
            .help("Leave a star on GitHub")
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local processing")
                        .font(.callout.weight(.medium))
                    Text("Your files are processed on this Mac. Nothing leaves it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
    }
}
