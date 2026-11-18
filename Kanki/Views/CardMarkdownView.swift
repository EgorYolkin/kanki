import SwiftUI

struct CardMarkdownView: View {
    let source: String

    var body: some View {
        ParsedCardText(source: source, isPreview: false).equatable()
    }
}

struct CardQuestionPreview: View {
    let source: String

    var body: some View {
        ParsedCardText(source: source, isPreview: true).equatable()
    }
}

/// The parser runs inside this boundary, not when a parent reconstructs a row
/// to update its due date, selection, or rating controls.
private struct ParsedCardText: View, Equatable {
    let source: String
    let isPreview: Bool

    var body: some View {
        let document = CardMarkdown(source: source)
        if isPreview {
            Text(verbatim: document.preview)
                .lineLimit(1)
        } else {
            MarkdownBlocks(blocks: document.blocks)
        }
    }
}

private struct MarkdownBlocks: View {
    let blocks: [CardMarkdown.Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks.indices, id: \.self) { index in
                blockView(blocks[index])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: CardMarkdown.Block) -> some View {
        switch block {
        case .paragraph(let content):
            Text(content)
        case let .heading(level, text):
            Text(text)
                .font(headingFont(level))
                .accessibilityAddTraits(.isHeader)
        case .code(let code):
            ScrollView(.horizontal) {
                Text(verbatim: code)
                    .font(.system(.body, design: .monospaced))
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(8)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        case let .list(start, items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(items.indices, id: \.self) { index in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: start.map { "\($0 + UInt(index))." } ?? "•")
                        MarkdownBlocks(blocks: items[index])
                    }
                }
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }
}
