import PDFKit
import SwiftUI

struct DetailView: View {
    @Bindable var library: Library
    @Bindable var player: Player
    let association: FileAssociation
    @Binding var showExport: Bool
    @AppStorage("hideDefaultAppTip") private var hideDefaultAppTip = false

    var body: some View {
        Group {
            if let item = library.selectedItem {
                ItemDetail(library: library, player: player, item: item, showExport: $showExport)
                    .id(item.id)
            } else if library.selection.count > 1 {
                MultiSelection(library: library, showExport: $showExport)
            } else {
                ContentUnavailableView {
                    Label("Select a File", systemImage: "text.bubble")
                } description: {
                    Text("Drop WhatsApp audio, video, PDFs or images to turn them into text.")
                } actions: {
                    Button("Import…") { library.importPanel() }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if !association.isDefault && !hideDefaultAppTip {
                        DefaultAppTip(association: association) { hideDefaultAppTip = true }
                            .padding(24)
                    }
                }
            }
        }
        .frame(minWidth: 420)
        .onChange(of: library.selectedItem?.id, initial: true) {
            player.load(library.selectedItem)
        }
    }
}

// MARK: - Single file

private enum DetailTab: String, CaseIterable {
    case transcript, subtitles
}

/// A displayed paragraph and its source segments (to edit without losing timings).
private struct Paragraph: Identifiable {
    var segment: Segment
    var sources: [UUID]
    var id: UUID { segment.id }
}

private struct ItemDetail: View {
    @Bindable var library: Library
    @Bindable var player: Player
    let item: LibraryItem
    @Binding var showExport: Bool

    @State private var tab: DetailTab = .transcript
    @State private var editing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if !item.kind.isDocument { tabs }
            Divider().padding(.horizontal, 24)
            content
            if !item.kind.isDocument {
                Divider()
                PlayerBar(player: player)
            } else {
                Divider()
                DocumentPreview(item: item)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.status == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    }
                }
                Text(meta)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { library.toggleFavorite(item.id) } label: {
                Image(systemName: item.favorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(item.favorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help(item.favorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"))

            Menu {
                Button(item.segments.isEmpty ? String(localized: "Transcribe") : String(localized: "Transcribe Again")) { library.enqueue([item.id]) }
                    .disabled(item.status.isActive)
                Button(editing ? String(localized: "Done Editing") : String(localized: "Edit Text")) { editing.toggle() }
                    .disabled(item.segments.isEmpty || item.status.isActive)
                Button("Copy Text") { library.copyText(item) }
                    .disabled(item.segments.isEmpty)
                Divider()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                Button("Open with Default App") { NSWorkspace.shared.open(item.url) }
                Divider()
                Button("Move to Trash", role: .destructive) { library.trash([item.id]) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3)
                    .frame(width: 28, height: 24)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private var meta: String {
        var parts: [String] = []
        if let id = item.localeID { parts.append(library.localeName(id).components(separatedBy: " (").first ?? id) }
        if item.duration > 0 { parts.append(item.duration.clock) }
        if item.kind == .pdf, item.pages > 0 { parts.append(String(localized: "\(item.pages) pages")) }
        if item.status == .done, let when = item.modified {
            let date = when.friendlyInline
            let seconds = item.elapsed.map { $0.formatted(.number.precision(.fractionLength(1))) }
            switch (item.kind.isDocument, seconds) {
            case (true, let s?): parts.append(String(localized: "Text extracted \(date) in \(s) s"))
            case (true, nil): parts.append(String(localized: "Text extracted \(date)"))
            case (false, let s?): parts.append(String(localized: "Transcribed \(date) in \(s) s"))
            case (false, nil): parts.append(String(localized: "Transcribed \(date)"))
            }
        } else {
            parts.append(String(localized: "Added \(item.added.friendlyInline)"))
        }
        return parts.joined(separator: " · ")
    }

    private var tabs: some View {
        HStack(spacing: 22) {
            tabButton("Transcript", .transcript)
            tabButton("Subtitles", .subtitles)
            Spacer()
            if editing {
                Button("Done") { editing = false }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }

    private func tabButton(_ title: LocalizedStringKey, _ value: DetailTab) -> some View {
        Button { tab = value } label: {
            VStack(spacing: 7) {
                Text(title)
                    .font(.body.weight(tab == value ? .semibold : .regular))
                    .foregroundStyle(tab == value ? Color.accentColor : .secondary)
                Rectangle()
                    .fill(tab == value ? Color.accentColor : .clear)
                    .frame(height: 2)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch item.status {
        case .failed(let message) where item.segments.isEmpty:
            stateView(icon: "exclamationmark.triangle.fill", tint: .red, title: String(localized: "Could Not Process"), detail: message) {
                Button("Retry") { library.enqueue([item.id]) }
                    .buttonStyle(.borderedProminent)
            }
        case .pending where item.segments.isEmpty:
            stateView(
                icon: item.kind.isDocument ? "doc.text.viewfinder" : "waveform",
                tint: .secondary,
                title: item.kind.isDocument ? String(localized: "Text Not Extracted Yet") : String(localized: "Not Transcribed Yet"),
                detail: item.fileExists ? String(localized: "Press Transcribe (⌘R).") : String(localized: "The original file can’t be found.")
            ) {
                Button("Transcribe") { library.enqueue([item.id]) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!item.fileExists)
            }
        case .queued where item.segments.isEmpty:
            stateView(icon: "clock", tint: .secondary, title: String(localized: "Waiting"), detail: String(localized: "It will start as soon as the previous one finishes.")) {
                Button("Cancel") { library.cancel(item.id) }
            }
        case .working(let p) where item.segments.isEmpty:
            stateView(icon: nil, tint: .secondary, title: item.kind.isDocument ? String(localized: "Recognizing text…") : String(localized: "Transcribing…"),
                      detail: p > 0 ? p.formatted(.percent.precision(.fractionLength(0))) : String(localized: "Preparing model…")) {
                Button("Cancel") { library.cancel(item.id) }
            }
        default:
            if tab == .subtitles && !item.kind.isDocument {
                subtitles
            } else {
                transcript
            }
        }
    }

    private func stateView<A: View>(icon: String?, tint: Color, title: String, detail: String,
                                    @ViewBuilder actions: () -> A) -> some View {
        VStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 34)).foregroundStyle(tint)
            } else {
                ProgressView().controlSize(.large)
            }
            Text(title).font(.title3.weight(.semibold))
            Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paragraphs: [Paragraph] {
        guard !item.kind.isDocument else { return item.segments.map { Paragraph(segment: $0, sources: [$0.id]) } }
        var out: [Paragraph] = []
        for seg in item.segments {
            if var last = out.last,
               seg.start - last.segment.end < 1.2,
               last.segment.text.count + seg.text.count < 320 {
                last.segment.text += " " + seg.text
                last.segment.end = max(last.segment.end, seg.end)
                last.sources.append(seg.id)
                out[out.count - 1] = last
            } else {
                out.append(Paragraph(segment: seg, sources: [seg.id]))
            }
        }
        return out
    }

    private var transcript: some View {
        let paras = paragraphs
        let current = player.isPlaying || player.currentTime > 0
            ? paras.last { $0.segment.start <= player.currentTime + 0.05 }?.id
            : nil
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(paras) { para in
                        ParagraphRow(
                            para: para,
                            kind: item.kind,
                            showTime: library.showTimestamps && item.kind != .image,
                            isCurrent: para.id == current,
                            query: library.search,
                            editing: editing,
                            onSeek: { player.play(from: para.segment.start) },
                            onEdit: { text in
                                library.edit(item.id, paragraph: para.segment, sources: para.sources, text: text)
                            }
                        )
                        .id(para.id)
                    }
                    if case .working(let p) = item.status {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Transcribing… \(p.formatted(.percent.precision(.fractionLength(0))))")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)
                        .padding(.leading, library.showTimestamps ? 72 : 0)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .onChange(of: current) { _, id in
                if let id, player.isPlaying { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private var subtitles: some View {
        let cues = Exporter.cues(item.segments)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(cues.enumerated()), id: \.offset) { index, cue in
                    let isCurrent = player.currentTime >= cue.start && player.currentTime < cue.end
                    Button { player.play(from: cue.start) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 26, alignment: .trailing)
                            Text("\(cue.start.stamp) → \(cue.end.stamp)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            Text(highlighted(cue.text, query: library.search))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isCurrent ? Color.accentColor.opacity(0.1) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 16) {
            if case .working = item.status {
                Button("Cancel", systemImage: "stop.circle") { library.cancel(item.id) }
            }
            Spacer()
            Text("\(item.wordCount) words")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Divider().frame(height: 16)
            Button("Copy", systemImage: "doc.on.doc") { library.copyText(item) }
                .disabled(item.segments.isEmpty)
            Button("Export", systemImage: "square.and.arrow.up") { showExport = true }
                .disabled(item.segments.isEmpty)
        }
        .buttonStyle(.borderless)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

private struct ParagraphRow: View {
    let para: Paragraph
    let kind: FileKind
    let showTime: Bool
    let isCurrent: Bool
    let query: String
    let editing: Bool
    let onSeek: () -> Void
    let onEdit: (String) -> Void

    @State private var draft = ""
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            if showTime {
                Button(action: onSeek) {
                    Text(Exporter.label(para.segment, kind: kind))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                        .frame(width: kind == .pdf ? 72 : 56, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(kind.isDocument)
                .help(kind.isDocument ? "" : String(localized: "Play from here"))
            }
            if editing {
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .onAppear { draft = para.segment.text }
                    .onSubmit { commit() }
                    .onChange(of: editing) { commit() }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.5)))
                    .onDisappear { commit() }
            } else {
                Text(highlighted(para.segment.text, query: query))
                    .font(.system(size: 16))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? Color.accentColor.opacity(0.09) : (hovering && !kind.isDocument ? Color.primary.opacity(0.03) : .clear))
        )
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { if !kind.isDocument && !editing { onSeek() } }
    }

    private func commit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, text != para.segment.text { onEdit(text) }
    }
}

/// Thumbnail for PDFs and images, in place of the player.
private struct DocumentPreview: View {
    let item: LibraryItem
    @State private var image: NSImage?

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    KindTile(item: item, size: 44)
                }
            }
            .frame(width: 70, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(radius: 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.kind == .pdf ? String(localized: "PDF Document") : String(localized: "Image"))
                    .font(.callout.weight(.medium))
                Text("Text taken from the PDF text layer or optical recognition (Vision), on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Original") { NSWorkspace.shared.open(item.url) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .task(id: item.id) {
            if item.kind == .pdf {
                image = PDFDocument(url: item.url)?.page(at: 0)?.thumbnail(of: CGSize(width: 140, height: 180), for: .mediaBox)
            } else {
                image = NSImage(contentsOf: item.url)
            }
        }
    }
}

// MARK: - Default app tip

/// Offers to open WhatsApp voice notes with Opus Lite on double-click.
private struct DefaultAppTip: View {
    let association: FileAssociation
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(for: FileAssociation.voiceNoteType))
                .resizable()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open .opus files with Opus Lite")
                    .font(.callout.weight(.semibold))
                Text("Double-click a WhatsApp voice note in Finder to transcribe it here. Now they open with \(association.currentName ?? String(localized: "no app")).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Make Default") { association.makeDefault() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(14)
        .frame(width: 520)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.quaternary.opacity(0.6)))
    }
}

// MARK: - Multiple selection

private struct MultiSelection: View {
    @Bindable var library: Library
    @Binding var showExport: Bool

    var body: some View {
        let items = library.selectedItems
        VStack(spacing: 16) {
            ZStack {
                ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { i, item in
                    KindTile(item: item, size: 56)
                        .rotationEffect(.degrees(Double(i - 1) * 8))
                        .offset(x: CGFloat(i - 1) * 18)
                }
            }
            .frame(height: 70)
            Text("\(items.count) files selected")
                .font(.title3.weight(.semibold))
            Text("\(items.filter { $0.status == .done }.count) transcribed · \(items.reduce(0) { $0 + $1.wordCount }) words")
                .foregroundStyle(.secondary)
            HStack {
                Button("Transcribe") { library.transcribeSelection() }
                    .buttonStyle(.borderedProminent)
                Button("Export…") { showExport = true }
                    .disabled(!items.contains { !$0.segments.isEmpty })
                Button("Move to Trash") { library.trash(library.selection) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
