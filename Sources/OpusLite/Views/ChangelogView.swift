import SwiftUI

/// *What's New*: the bundled CHANGELOG.md, drawn with a small Markdown subset
/// (headings, paragraphs, bullets and inline styles).
struct ChangelogView: View {
    private let blocks: [Block] = {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Block.parse(text)
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
            .textSelection(.enabled)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .frame(minWidth: 480, minHeight: 420)
    }

    @ViewBuilder private func view(for block: Block) -> some View {
        switch block {
        case .title(let text):
            Text(inline(text)).font(.largeTitle.weight(.semibold))
        case .version(let text):
            Text(inline(text)).font(.title2.weight(.semibold)).padding(.top, 18)
        case .section(let text):
            Text(inline(text)).font(.headline).padding(.top, 6)
        case .paragraph(let text):
            Text(inline(text)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.tertiary)
                Text(inline(text)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    enum Block {
        case title(String), version(String), section(String), paragraph(String), bullet(String)

        static func parse(_ text: String) -> [Block] {
            var out: [Block] = []
            var paragraph: [String] = []
            func flush() {
                if !paragraph.isEmpty { out.append(.paragraph(paragraph.joined(separator: " "))) }
                paragraph = []
            }
            for raw in text.components(separatedBy: .newlines) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { flush(); continue }
                if line.hasPrefix("### ") { flush(); out.append(.section(String(line.dropFirst(4)))) }
                else if line.hasPrefix("## ") { flush(); out.append(.version(String(line.dropFirst(3)))) }
                else if line.hasPrefix("# ") { flush(); out.append(.title(String(line.dropFirst(2)))) }
                else if line.hasPrefix("- ") { flush(); out.append(.bullet(String(line.dropFirst(2)))) }
                else { paragraph.append(line) }
            }
            flush()
            return out
        }
    }
}
