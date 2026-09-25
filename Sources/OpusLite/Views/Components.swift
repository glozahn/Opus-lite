import SwiftUI

/// Icono de tipo de archivo en baldosa de color, como en Finder/Música.
struct KindTile: View {
    let item: LibraryItem
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [style.color.opacity(0.85), style.color], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: style.color.opacity(0.25), radius: 2, y: 1)
    }

    private var style: (symbol: String, color: Color) {
        switch item.kind {
        case .audio:
            let ext = item.url.pathExtension.lowercased()
            return ["opus", "ogg", "oga"].contains(ext)
                ? ("music.note", Color(red: 0.25, green: 0.52, blue: 0.96))
                : ("waveform", Color(red: 0.55, green: 0.36, blue: 0.93))
        case .video: return ("film", Color(red: 0.36, green: 0.40, blue: 0.46))
        case .pdf: return ("doc.richtext", Color(red: 0.90, green: 0.26, blue: 0.24))
        case .image: return ("photo", Color(red: 0.96, green: 0.58, blue: 0.16))
        }
    }
}

/// Etiqueta en cápsula ("OCR", "Pendiente"…).
struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(.quaternary))
            .foregroundStyle(.secondary)
    }
}

/// Resalta coincidencias de búsqueda dentro de un texto.
func highlighted(_ text: String, query: String) -> AttributedString {
    var out = AttributedString(text)
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return out }
    var range = out.startIndex..<out.endIndex
    while let found = out[range].range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
        out[found].backgroundColor = Color.accentColor.opacity(0.22)
        out[found].foregroundColor = Color.accentColor
        range = found.upperBound..<out.endIndex
    }
    return out
}

extension Date {
    /// "Hoy, 17:09" · "Ayer, 20:15" · "12 sept, 09:30"
    var friendly: String {
        let cal = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(self) { return "Hoy, \(time)" }
        if cal.isDateInYesterday(self) { return "Ayer, \(time)" }
        return formatted(.dateTime.day().month(.abbreviated)) + ", " + time
    }
}
