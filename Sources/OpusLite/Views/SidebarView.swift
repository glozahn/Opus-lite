import SwiftUI

struct SidebarView: View {
    @Bindable var library: Library

    var body: some View {
        List(selection: Binding(get: { library.filter }, set: { if let f = $0 { library.filter = f } })) {
            Section("Biblioteca") {
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
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Procesamiento local")
                        .font(.callout.weight(.medium))
                    Text("Tus archivos se procesan en este Mac. Nada sale a internet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
    }
}
