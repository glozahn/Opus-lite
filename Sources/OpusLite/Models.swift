import Foundation
import UniformTypeIdentifiers

/// Tramo de texto con su posición en el audio (o página, en documentos).
struct Segment: Codable, Hashable, Identifiable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

enum FileKind: String, Codable {
    case audio, video, pdf, image

    static func detect(_ url: URL) -> FileKind? {
        let ext = url.pathExtension.lowercased()
        if ["opus", "ogg", "oga"].contains(ext) { return .audio }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return nil
    }

    var isDocument: Bool { self == .pdf || self == .image }
}

enum ItemStatus: Codable, Equatable {
    case pending
    case queued
    case working(Double)
    case done
    case failed(String)

    var isActive: Bool {
        switch self {
        case .queued, .working: true
        default: false
        }
    }
}

struct LibraryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var path: String
    var added = Date()
    var kind: FileKind
    var duration: TimeInterval = 0
    var pages = 0
    var status: ItemStatus = .pending
    var segments: [Segment] = []
    var localeID: String?
    var engine: Engine?
    var elapsed: TimeInterval?
    var favorite = false
    var trashed: Date?
    var modified: Date?

    var url: URL { URL(fileURLWithPath: path) }
    var name: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
    var fileExists: Bool { FileManager.default.fileExists(atPath: path) }

    var text: String {
        segments.map(\.text).joined(separator: kind.isDocument ? "\n\n" : " ")
    }

    var wordCount: Int {
        segments.reduce(0) { $0 + $1.text.split { $0.isWhitespace }.count }
    }
}

enum SidebarFilter: String, CaseIterable, Identifiable, Hashable {
    case all, recent, favorites, processing, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Todos los archivos"
        case .recent: "Recientes"
        case .favorites: "Favoritos"
        case .processing: "En proceso"
        case .trash: "Papelera"
        }
    }

    var icon: String {
        switch self {
        case .all: "doc.on.doc"
        case .recent: "clock"
        case .favorites: "star"
        case .processing: "arrow.triangle.2.circlepath"
        case .trash: "trash"
        }
    }

    func includes(_ item: LibraryItem) -> Bool {
        switch self {
        case .trash: return item.trashed != nil
        case _ where item.trashed != nil: return false
        case .all: return true
        case .recent: return item.added > Date().addingTimeInterval(-7 * 86_400)
        case .favorites: return item.favorite
        case .processing:
            if case .failed = item.status { return true }
            return item.status.isActive
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case newest, oldest, name, duration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: "Más recientes"
        case .oldest: "Más antiguos"
        case .name: "Nombre"
        case .duration: "Duración"
        }
    }
}

extension TimeInterval {
    /// 1:05 · 1:02:07
    var clock: String {
        let total = Int(self.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// 00:18
    var stamp: String {
        let total = Int(self.rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
