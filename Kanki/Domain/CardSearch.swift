import Foundation

/// Поиск по демо-карточкам: пустой запрос возвращает все карточки,
/// иначе — совпадения по вопросу или ответу без учёта регистра.
enum CardSearch {
    static func filter(_ cards: [SessionCard], matching query: String) -> [SessionCard] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return cards }
        return cards.filter {
            $0.question.localizedCaseInsensitiveContains(trimmed) ||
            $0.answer.localizedCaseInsensitiveContains(trimmed)
        }
    }
}
