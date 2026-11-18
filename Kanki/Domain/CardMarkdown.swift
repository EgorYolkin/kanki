import Foundation
import Markdown

/// Read-only presentation of one card field. Never used to rebuild the stored Markdown.
struct CardMarkdown {
    enum Block: Equatable {
        case paragraph(AttributedString)
        case heading(level: Int, text: AttributedString)
        case code(String)
        case list(start: UInt?, items: [[Block]])
    }

    let blocks: [Block]

    init(source: String) {
        let document = Document(parsing: source, options: .disableSmartOpts)
        if document.isEmpty, !source.isEmpty {
            // CommonMark can consume an entire field as invisible reference definitions.
            blocks = [.paragraph(AttributedString(source))]
        } else {
            blocks = Renderer(source: source).blocks(in: document)
        }
    }

    var preview: String {
        var result = ""
        for block in blocks { block.appendPreview(to: &result) }
        return result
    }
}

private extension CardMarkdown.Block {
    func appendPreview(to result: inout String) {
        switch self {
        case .paragraph(let text), .heading(_, let text):
            Self.appendWords(text.characters, to: &result)
        case .code(let code):
            Self.appendWords(code, to: &result)
        case .list(_, let items):
            for item in items {
                for block in item { block.appendPreview(to: &result) }
            }
        }
    }

    static func appendWords(_ characters: some Sequence<Character>, to result: inout String) {
        var needsSpace = !result.isEmpty
        for character in characters {
            if character.isWhitespace {
                needsSpace = !result.isEmpty
            } else {
                if needsSpace { result.append(" ") }
                result.append(character)
                needsSpace = false
            }
        }
    }
}

private final class Renderer {
    private let source: String
    // cmark addresses original text by line and UTF-8 byte column. Only build this index
    // when a construct outside our supported subset actually needs its literal source.
    private lazy var lines = source.split(omittingEmptySubsequences: false) {
        $0 == "\n" || $0 == "\r" || $0 == "\r\n"
    }

    init(source: String) {
        self.source = source
    }

    func blocks(in node: Markup) -> [CardMarkdown.Block] {
        node.children.map(block)
    }

    private func block(_ node: Markup) -> CardMarkdown.Block {
        switch node {
        case let heading as Heading:
            return .heading(level: heading.level, text: inlineContent(of: heading))
        case is Paragraph:
            return .paragraph(inlineContent(of: node))
        case let code as CodeBlock:
            return .code(code.code)
        case let list as OrderedList:
            return listBlock(list, start: list.startIndex)
        case let list as UnorderedList:
            return listBlock(list, start: nil)
        default:
            return .paragraph(AttributedString(literalSource(of: node)))
        }
    }

    private func listBlock(_ list: any ListItemContainer, start: UInt?) -> CardMarkdown.Block {
        // A task list isn't an interactive checklist here; retain its literal markers.
        if list.listItems.contains(where: { $0.checkbox != nil }) {
            return .paragraph(AttributedString(literalSource(of: list)))
        }
        return .list(start: start, items: list.listItems.map { blocks(in: $0) })
    }

    private func inlineContent(of node: Markup) -> AttributedString {
        var text = AttributedString()
        appendChildren(of: node, attributes: AttributeContainer(), to: &text)
        return text
    }

    private func appendChildren(of node: Markup, attributes: AttributeContainer, to result: inout AttributedString) {
        for child in node.children {
            append(child, attributes: attributes, to: &result)
        }
    }

    private func append(_ node: Markup, attributes: AttributeContainer, to result: inout AttributedString) {
        var attributes = attributes
        switch node {
        case is Strong:
            attributes.inlinePresentationIntent = (attributes.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
        case is Emphasis:
            attributes.inlinePresentationIntent = (attributes.inlinePresentationIntent ?? []).union(.emphasized)
        case let link as Link:
            attributes.link = Self.webURL(link.destination)
            if link.isEmpty {
                result.append(AttributedString(link.destination ?? literalSource(of: node), attributes: attributes))
                return
            }
        case is Image where !node.isEmpty:
            // Visit only the caption's inline children, never the remote resource.
            break
        default:
            appendLeaf(node, attributes: attributes, to: &result)
            return
        }
        appendChildren(of: node, attributes: attributes, to: &result)
    }

    private func appendLeaf(_ node: Markup, attributes: AttributeContainer, to result: inout AttributedString) {
        var attributes = attributes
        let value: String
        switch node {
        case let text as Markdown.Text:
            value = text.string
        case let code as InlineCode:
            attributes.inlinePresentationIntent = (attributes.inlinePresentationIntent ?? []).union(.code)
            value = code.code
        case is LineBreak, is SoftBreak:
            value = "\n"
        case let html as InlineHTML:
            value = html.rawHTML
        default:
            value = literalSource(of: node)
        }
        result.append(AttributedString(value, attributes: attributes))
    }

    private static func webURL(_ destination: String?) -> URL? {
        guard let destination, let url = URL(string: destination, encodingInvalidCharacters: false),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private func literalSource(of node: Markup) -> String {
        guard let range = node.range,
              let lower = index(at: range.lowerBound), let upper = index(at: range.upperBound), lower < upper,
              let literal = String(bytes: source.utf8[lower..<upper], encoding: .utf8) else { return node.format() }
        return literal
    }

    private func index(at location: SourceLocation) -> String.Index? {
        guard lines.indices.contains(location.line - 1), location.column > 0 else { return nil }
        let line = lines[location.line - 1].utf8
        return line.index(line.startIndex, offsetBy: location.column - 1, limitedBy: line.endIndex)
    }
}
