import SwiftUI

struct FileListView: View {
    @Bindable var library: Library
    @State private var isTargeted = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        let items = library.visibleItems
        VStack(spacing: 0) {
            header
            searchField
            if library.filter != .trash { dropZone }
            if items.isEmpty {
                emptyState
            } else {
                List(selection: $library.selection) {
                    ForEach(items) { item in
                        FileRow(item: item, query: library.search) { library.enqueue([item.id]) }
                            .tag(item.id)
                            .contextMenu { menu(for: item) }
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
                .onDeleteCommand { deleteSelection() }
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 460)
        .dropDestination(for: URL.self) { urls, _ in
            library.add(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    private var header: some View {
        HStack {
            Text(library.filter == .all ? String(localized: "Files") : library.filter.title)
                .font(.headline)
            Spacer()
            if library.filter == .trash, library.count(.trash) > 0 {
                Button("Empty Trash", role: .destructive) { library.emptyTrash() }
                    .buttonStyle(.borderless)
                    .font(.callout)
            } else {
                Menu {
                    Picker("Sort", selection: $library.sort) {
                        ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(library.sort.title).font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// The column's own search field: filters this list and highlights matches in the text.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search files, transcripts…", text: $library.search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { library.search = ""; searchFocused = false }
            if !library.search.isEmpty {
                Button { library.search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.quaternary.opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(searchFocused ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 2)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in searchFocused = true }
    }

    private var dropZone: some View {
        VStack(spacing: 4) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            Text("Drop files here")
                .font(.callout)
                .foregroundStyle(isTargeted ? Color.accentColor : .primary)
            Text("Audio · Video · PDF · Images")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        )
        .contentShape(Rectangle())
        .onTapGesture { library.importPanel() }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .help("Click to choose files")
    }

    @ViewBuilder private var emptyState: some View {
        if !library.search.isEmpty {
            ContentUnavailableView.search(text: library.search)
        } else {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: library.filter.icon)
            } description: {
                Text(emptyDetail)
            }
        }
    }

    private var emptyTitle: String {
        switch library.filter {
        case .all, .recent: String(localized: "No Files")
        case .favorites: String(localized: "No Favorites")
        case .processing: String(localized: "Nothing in Progress")
        case .trash: String(localized: "Trash Is Empty")
        }
    }

    private var emptyDetail: String {
        switch library.filter {
        case .all, .recent: String(localized: "Drop WhatsApp voice notes, audio, video, PDFs or images.")
        case .favorites: String(localized: "Star files to keep them handy.")
        case .processing: String(localized: "The transcription queue and errors show up here.")
        case .trash: String(localized: "Removed files show up here.")
        }
    }

    @ViewBuilder private func menu(for item: LibraryItem) -> some View {
        let ids = library.selection.contains(item.id) ? library.selection : [item.id]
        if item.trashed != nil {
            Button("Restore") { library.restore(ids) }
            Button("Remove from Library", role: .destructive) { library.removeForever(ids) }
        } else {
            Button(item.segments.isEmpty ? String(localized: "Transcribe") : String(localized: "Transcribe Again")) { library.enqueue(Array(ids)) }
                .disabled(item.status.isActive)
            if item.status.isActive {
                Button("Cancel") { library.cancel(item.id) }
            }
            Button(item.favorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites")) { library.toggleFavorite(item.id) }
            Divider()
            Button("Copy Text") { library.copyText(item) }
                .disabled(item.segments.isEmpty)
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
            Divider()
            Button("Move to Trash", role: .destructive) { library.trash(ids) }
        }
    }

    private func deleteSelection() {
        if library.filter == .trash {
            library.removeForever(library.selection)
        } else {
            library.trash(library.selection)
        }
    }
}

struct FileRow: View {
    let item: LibraryItem
    let query: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            KindTile(item: item)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(highlighted(item.name, query: query))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.favorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            status
        }
        .padding(.vertical, 5)
        .opacity(item.fileExists ? 1 : 0.5)
    }

    private var subtitle: String {
        var parts = [item.added.friendly]
        if item.duration > 0 { parts.append(item.duration.clock) }
        if item.kind == .pdf, item.pages > 0 { parts.append(String(localized: "\(item.pages) pp.")) }
        if !item.fileExists { parts = [String(localized: "File not found")] }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var status: some View {
        switch item.status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17))
                .foregroundStyle(.green)
        case .working(let p):
            HStack(spacing: 8) {
                ProgressView(value: p)
                    .frame(width: 60)
                Text(p, format: .percent.precision(.fractionLength(0)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        case .queued:
            Label("Waiting", systemImage: "clock")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .failed(let message):
            HStack(spacing: 8) {
                Label("Error", systemImage: "exclamationmark.circle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .help(message)
                Button(action: onRetry) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .help("Retry")
            }
        case .pending:
            Tag(text: item.kind.isDocument ? "OCR" : String(localized: "Pending"))
        }
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("OpusLiteFocusSearch")
}
