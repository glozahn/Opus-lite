import SwiftUI

/// File-type icon on a colored tile, like Finder/Music.
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

/// Capsule tag ("OCR", "Pending"…).
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

/// Highlights search matches in a text.
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
    /// "Today, 17:09" · "Yesterday, 20:15" · "Sep 12, 09:30"
    var friendly: String {
        let cal = Calendar.current
        let time = formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(self) { return String(localized: "Today, \(time)") }
        if cal.isDateInYesterday(self) { return String(localized: "Yesterday, \(time)") }
        return formatted(.dateTime.day().month(.abbreviated)) + ", " + time
    }

    /// Same as `friendly`, lowercased for use inside a sentence ("Transcribed today, 17:09").
    var friendlyInline: String {
        let cal = Calendar.current
        guard cal.isDateInToday(self) || cal.isDateInYesterday(self) else { return friendly }
        return friendly.prefix(1).lowercased() + friendly.dropFirst()
    }
}
