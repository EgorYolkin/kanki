import Foundation

/// Операция переименования категории, передаваемая в снапшоте.
/// Загружающая сторона применяет её к `card.deck` с префиксом `from`,
/// чтобы переименование не превратилось в «удаление + создание».
struct DeckRename: Codable, Equatable {
    let from: String
    let to: String

    enum CodingKeys: String, CodingKey {
        case from
        case to
    }
}

/// Сводка категории для списка на экране «Обучение».
struct CategorySummary: Equatable {
    /// `nil` — служебная секция «Без категории».
    let deck: String?
    /// Карточки с due ≤ сейчас (включая новые).
    let dueCount: Int
    /// Всего карточек в категории и её подкатегориях (по префиксу `::`).
    let totalCount: Int
    /// Карточки без единой оценки — для подписи «+M новых».
    let newCount: Int

    var title: String {
        deck ?? CardCategory.noCategoryTitle
    }
}

/// Правила категорий: имена, валидация, счётчики и операции над снапшотом.
/// Категория — производная от имён `card.deck`; отдельной таблицы нет.
enum CardCategory {
    static let noCategoryTitle = "Без категории"
    static let hierarchySeparator = "::"

    /// Нормализует имя: обрезает пробелы, пустое → `nil` («Без категории»).
    static func trimmedDeck(_ deck: String?) -> String? {
        guard let trimmed = deck?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed
    }

    /// Ошибка валидации нового имени категории; `nil` — имя допустимо.
    /// Правила спеки ux-categories-spec §3: непустое, без `::`, не «Без категории»,
    /// без дубликатов.
    static func validationError(
        for name: String,
        existingDecks: Set<String?>
    ) -> String? {
        guard let trimmed = trimmedDeck(name) else {
            return "Введите имя категории"
        }
        if trimmed.contains(hierarchySeparator) {
            return "Имя не может содержать «::» — вложенность появится позже"
        }
        if trimmed == noCategoryTitle {
            return "Имя «\(noCategoryTitle)» зарезервировано"
        }
        if existingDecks.contains(trimmed) {
            return "Категория с таким именем уже есть"
        }
        return nil
    }

    /// Карточки категории и её подкатегорий: точное совпадение имени
    /// или префикс `имя::` (семантика Anki: выбор колоды включает подколоды).
    /// По умолчанию архивные карточки не учитываются.
    static func cards(
        _ cards: [SessionCard],
        inDeck deck: String?,
        includingArchived: Bool = false
    ) -> [SessionCard] {
        let active = includingArchived ? cards : cards.filter { !$0.isArchived }
        guard let deck else {
            return active.filter { $0.deck == nil }
        }
        let prefix = deck + hierarchySeparator
        return active.filter { card in
            guard let cardDeck = card.deck else { return false }
            return cardDeck == deck || cardDeck.hasPrefix(prefix)
        }
    }

    /// Имена категорий в наборе карточек, по алфавиту.
    static func deckNames(in cards: [SessionCard]) -> [String] {
        Set(cards.compactMap(\.deck)).sorted()
    }

    /// Карточки активные (`archived: false`) или архивные — для списка «Все карточки».
    static func cards(_ cards: [SessionCard], archived: Bool) -> [SessionCard] {
        cards.filter { $0.isArchived == archived }
    }

    /// Список категорий с счётчиками: по алфавиту, «Без категории» — в конце.
    /// Пустая секция «Без категории» возвращается только когда других категорий нет.
    static func summaries(
        of snapshot: LearningSnapshot,
        at date: Date
    ) -> [CategorySummary] {
        let reviewedIDs = Set(snapshot.reviews.map(\.cardID))
        let dueIDs = Set(
            ReviewQueue.cards(snapshot.cards, schedules: snapshot.schedules, at: date)
                .map(\.id)
        )
        let activeCards = snapshot.cards.filter { !$0.isArchived }
        let decks = Set(activeCards.compactMap(\.deck))

        var summaries = decks
            .map { deck -> CategorySummary in
                let members = cards(snapshot.cards, inDeck: deck)
                return CategorySummary(
                    deck: deck,
                    dueCount: members.filter { dueIDs.contains($0.id) }.count,
                    totalCount: members.count,
                    newCount: members.filter { !reviewedIDs.contains($0.id) }.count
                )
            }
            .sorted {
                ($0.deck ?? "").localizedCaseInsensitiveCompare($1.deck ?? "") == .orderedAscending
            }

        let uncategorized = cards(snapshot.cards, inDeck: nil)
        if !uncategorized.isEmpty || summaries.isEmpty {
            summaries.append(
                CategorySummary(
                    deck: nil,
                    dueCount: uncategorized.filter { dueIDs.contains($0.id) }.count,
                    totalCount: uncategorized.count,
                    newCount: uncategorized.filter { !reviewedIDs.contains($0.id) }.count
                )
            )
        }
        return summaries
    }
}

extension LearningSnapshot {
    /// Переименовывает категорию (включая подкатегории по префиксу) и записывает
    /// операцию в `deck_renames` для синка. Новое имя должно пройти валидацию.
    mutating func renameDeck(from oldName: String, to newName: String) throws {
        let normalizedOld = CardCategory.trimmedDeck(oldName)
        let normalizedNew = CardCategory.trimmedDeck(newName)
        guard let old = normalizedOld, let new = normalizedNew else {
            throw CardCategoryError.invalidName
        }
        let currentDecks = Set(cards.compactMap(\.deck))
        guard currentDecks.contains(old) else {
            throw CardCategoryError(message: "Категория «\(old)» не найдена")
        }
        if let error = CardCategory.validationError(for: new, existingDecks: currentDecks) {
            throw CardCategoryError(message: error)
        }
        let prefix = old + CardCategory.hierarchySeparator
        for index in cards.indices {
            guard let deck = cards[index].deck else { continue }
            if deck == old {
                cards[index].deck = new
            } else if deck.hasPrefix(prefix) {
                cards[index].deck = new + deck.dropFirst(old.count)
            }
        }
        deckRenames.removeAll { $0.from == old }
        deckRenames.append(DeckRename(from: old, to: new))
    }

    /// Удаляет категорию: карточки уходят в «Без категории».
    /// Операция удаления передаётся отсутствием категории в снапшоте.
    mutating func deleteDeck(_ name: String) {
        let prefix = name + CardCategory.hierarchySeparator
        for index in cards.indices {
            guard let deck = cards[index].deck else { continue }
            if deck == name {
                cards[index].deck = nil
            } else if deck.hasPrefix(prefix) {
                cards[index].deck = String(deck.dropFirst(prefix.count))
            }
        }
    }
}

struct CardCategoryError: Error, Equatable {
    let message: String

    static let invalidName = CardCategoryError(message: "Недопустимое имя категории")
}
