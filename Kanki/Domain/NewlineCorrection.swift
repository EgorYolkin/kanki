import Foundation

/// Неизменяемый исходник и диапазоны буквальных пар; выбор не меняет исходник.
struct NewlineCorrection {
    struct Match: Identifiable {
        let id: Int
        fileprivate let range: Range<String.Index>
        let context: String
    }

    let source: String
    let matches: [Match]
    var selected: Set<Int> = []

    init(source: String) {
        self.source = source
        var matches: [Match] = []
        var start = source.startIndex
        while let range = source.range(of: #"\n"#, options: .literal, range: start..<source.endIndex) {
            let before = source[..<range.lowerBound].suffix(20)
            let after = source[range.upperBound...].prefix(20)
            matches.append(Match(id: matches.count, range: range, context: "\(before)⟦\\n⟧\(after)"))
            start = range.upperBound
        }
        self.matches = matches
    }

    var preview: String {
        guard !selected.isEmpty else { return source }
        var result = ""
        result.reserveCapacity(source.utf8.count)
        var start = source.startIndex
        for match in matches where selected.contains(match.id) {
            result += source[start..<match.range.lowerBound]
            result += "\n"
            start = match.range.upperBound
        }
        result += source[start...]
        return result
    }
}
