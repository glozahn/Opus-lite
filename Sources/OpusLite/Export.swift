import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case txt, docx, md, srt, vtt

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    var detail: String {
        switch self {
        case .txt: "Texto plano"
        case .docx: "Documento de Word"
        case .md: "Markdown"
        case .srt: "Subtítulos (SubRip)"
        case .vtt: "Subtítulos web (WebVTT)"
        }
    }

    var type: UTType {
        switch self {
        case .txt: .plainText
        case .docx: UTType(filenameExtension: "docx") ?? .data
        case .md: UTType(filenameExtension: "md") ?? .plainText
        case .srt: UTType(filenameExtension: "srt") ?? .plainText
        case .vtt: UTType(filenameExtension: "vtt") ?? .plainText
        }
    }

    var isSubtitle: Bool { self == .srt || self == .vtt }
}

enum Exporter {
    /// Párrafos para leer: une tramos cercanos para que el texto no quede troceado.
    static func paragraphs(_ segments: [Segment], kind: FileKind) -> [Segment] {
        guard !kind.isDocument else { return segments }
        var out: [Segment] = []
        for seg in segments {
            if var last = out.last,
               seg.start - last.end < 1.2,
               last.text.count + seg.text.count < 320,
               !last.text.hasSuffix("?"), !last.text.hasSuffix("!") || last.text.count < 60 {
                last.text += " " + seg.text
                last.end = max(last.end, seg.end)
                out[out.count - 1] = last
            } else {
                out.append(seg)
            }
        }
        return out
    }

    /// Cues de subtítulos de hasta ~84 caracteres (2 líneas), con el tiempo repartido por longitud.
    static func cues(_ segments: [Segment], maxChars: Int = 84) -> [Segment] {
        var out: [Segment] = []
        for seg in segments {
            let words = seg.text.split(separator: " ").map(String.init)
            var groups: [String] = []
            var current = ""
            for word in words {
                if !current.isEmpty, current.count + word.count + 1 > maxChars {
                    groups.append(current)
                    current = word
                } else {
                    current = current.isEmpty ? word : current + " " + word
                }
            }
            if !current.isEmpty { groups.append(current) }
            let total = max(groups.reduce(0) { $0 + $1.count }, 1)
            let span = max(seg.end - seg.start, 0.5)
            var t = seg.start
            for group in groups {
                let d = span * Double(group.count) / Double(total)
                out.append(Segment(start: t, end: t + d, text: group))
                t += d
            }
        }
        return out
    }

    static func text(_ item: LibraryItem, timestamps: Bool) -> String {
        paragraphs(item.segments, kind: item.kind).map { seg in
            timestamps ? "[\(label(seg, kind: item.kind))] \(seg.text)" : seg.text
        }.joined(separator: "\n\n")
    }

    static func markdown(_ item: LibraryItem, timestamps: Bool) -> String {
        var out = "# \(item.title)\n\n"
        for seg in paragraphs(item.segments, kind: item.kind) {
            out += timestamps ? "**\(label(seg, kind: item.kind))** \(seg.text)\n\n" : "\(seg.text)\n\n"
        }
        return out
    }

    static func srt(_ item: LibraryItem) -> String {
        cues(item.segments).enumerated().map { i, c in
            "\(i + 1)\n\(time(c.start, sep: ",")) --> \(time(c.end, sep: ","))\n\(wrap(c.text))\n"
        }.joined(separator: "\n")
    }

    static func vtt(_ item: LibraryItem) -> String {
        "WEBVTT\n\n" + cues(item.segments).map { c in
            "\(time(c.start, sep: ".")) --> \(time(c.end, sep: "."))\n\(wrap(c.text))\n"
        }.joined(separator: "\n")
    }

    static func data(_ item: LibraryItem, format: ExportFormat, timestamps: Bool) throws -> Data {
        switch format {
        case .txt: return Data(text(item, timestamps: timestamps).utf8)
        case .md: return Data(markdown(item, timestamps: timestamps).utf8)
        case .srt: return Data(srt(item).utf8)
        case .vtt: return Data(vtt(item).utf8)
        case .docx:
            let doc = NSMutableAttributedString()
            let title = NSFont.systemFont(ofSize: 20, weight: .semibold)
            let stamp = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            let body = NSFont.systemFont(ofSize: 12)
            let para = NSMutableParagraphStyle()
            para.paragraphSpacing = 10
            doc.append(NSAttributedString(string: item.title + "\n\n", attributes: [.font: title]))
            for seg in paragraphs(item.segments, kind: item.kind) {
                if timestamps {
                    doc.append(NSAttributedString(string: label(seg, kind: item.kind) + "\n",
                                                  attributes: [.font: stamp, .foregroundColor: NSColor.gray]))
                }
                doc.append(NSAttributedString(string: seg.text + "\n", attributes: [.font: body, .paragraphStyle: para]))
            }
            return try doc.data(from: NSRange(location: 0, length: doc.length),
                                documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        }
    }

    @MainActor
    static func save(_ item: LibraryItem, format: ExportFormat, timestamps: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = item.title + "." + format.rawValue
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data(item, format: format, timestamps: timestamps).write(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Un archivo por elemento en la carpeta elegida.
    @MainActor
    static func saveAll(_ items: [LibraryItem], format: ExportFormat, timestamps: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Exportar aquí"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        for item in items where !item.segments.isEmpty {
            let out = folder.appendingPathComponent(item.title).appendingPathExtension(format.rawValue)
            try? data(item, format: format, timestamps: timestamps).write(to: out)
        }
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    static func label(_ seg: Segment, kind: FileKind) -> String {
        kind == .pdf ? "Página \(Int(seg.start) + 1)" : seg.start.stamp
    }

    private static func time(_ t: TimeInterval, sep: String) -> String {
        let ms = Int((t * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d", ms / 3_600_000, (ms / 60_000) % 60, (ms / 1000) % 60, sep, ms % 1000)
    }

    /// Parte en dos líneas equilibradas si es largo.
    private static func wrap(_ text: String) -> String {
        guard text.count > 42 else { return text }
        let mid = text.index(text.startIndex, offsetBy: text.count / 2)
        if let space = text[mid...].firstIndex(of: " ") ?? text[..<mid].lastIndex(of: " ") {
            return text[..<space] + "\n" + text[text.index(after: space)...]
        }
        return text
    }
}
