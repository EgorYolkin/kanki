import Foundation

/// Очереди повторения. Основная — новые карточки и те, чей срок уже наступил;
/// досрочная — карточки с будущим сроком, когда основная пуста.
/// Архивные карточки в очереди не попадают.
enum ReviewQueue {
    /// Сортировка основной очереди: сначала меньший due (у новых — `createdAt`),
    /// затем более старые карточки, затем стабильный порядок по UUID.
    static func cards(
        _ cards: [SessionCard],
        schedules: [UUID: CardSchedule],
        at date: Date
    ) -> [SessionCard] {
        cards
            .filter { !$0.isArchived }
            .filter { schedules[$0.id].map { $0.due <= date } ?? true }
            .sorted { isOrderedBefore($0, $1, schedules: schedules) }
    }

    /// Досрочная очередь: запланированные карточки, чей срок ещё не наступил.
    /// Новые карточки без расписания сюда не попадают — они всегда «к повторению».
    /// Порядок: ближайший срок первым, затем старые карточки.
    static func aheadCards(
        _ cards: [SessionCard],
        schedules: [UUID: CardSchedule],
        at date: Date
    ) -> [SessionCard] {
        cards
            .filter { !$0.isArchived }
            .filter { schedules[$0.id].map { $0.due > date } ?? false }
            .sorted { isOrderedBefore($0, $1, schedules: schedules) }
    }

    /// Сеанс категории: новые и due-карточки, а после их завершения — досрочные.
    /// Фильтр категории сохраняет подкатегории и исключает архив.
    static func categoryCards(
        _ allCards: [SessionCard],
        inDeck deck: String?,
        schedules: [UUID: CardSchedule],
        at date: Date
    ) -> [SessionCard] {
        let selected = CardCategory.cards(allCards, inDeck: deck)
        let due = cards(selected, schedules: schedules, at: date)
        return due.isEmpty ? aheadCards(selected, schedules: schedules, at: date) : due
    }

    /// Режим уже выбранной очереди; пустая очередь не считается досрочной.
    static func isAheadReview(
        _ selectedCards: [SessionCard],
        schedules: [UUID: CardSchedule],
        at date: Date
    ) -> Bool {
        !selectedCards.isEmpty && selectedCards.allSatisfy { card in
            schedules[card.id].map { $0.due > date } ?? false
        }
    }

    private static func isOrderedBefore(
        _ lhs: SessionCard,
        _ rhs: SessionCard,
        schedules: [UUID: CardSchedule]
    ) -> Bool {
        let lhsDue = schedules[lhs.id]?.due ?? lhs.createdAt
        let rhsDue = schedules[rhs.id]?.due ?? rhs.createdAt
        if lhsDue != rhsDue {
            return lhsDue < rhsDue
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
