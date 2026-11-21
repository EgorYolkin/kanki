import Foundation

/// Очереди повторения. Основная — новые карточки и те, чей срок уже наступил;
/// досрочная — карточки с будущим сроком, когда основная пуста.
/// Архивные карточки в очереди не попадают.
enum ReviewQueue {
    enum Scope {
        case all
        case category(String?)
    }

    struct Selection {
        let cards: [SessionCard]
        let isAhead: Bool
    }

    /// Сортировка основной очереди: сначала меньший due (у новых — `createdAt`),
    /// затем более старые карточки, затем стабильный порядок по UUID.
    static func cards(
        _ cards: [SessionCard],
        schedules: [UUID: CardSchedule],
        at date: Date
    ) -> [SessionCard] {
        cards.lazy
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
        cards.lazy
            .filter { !$0.isArchived }
            .filter { schedules[$0.id].map { $0.due > date } ?? false }
            .sorted { isOrderedBefore($0, $1, schedules: schedules) }
    }

    /// В выбранной области досрочная очередь доступна только при пустой основной.
    static func select(
        _ allCards: [SessionCard],
        in scope: Scope,
        schedules: [UUID: CardSchedule],
        at date: Date
    ) -> Selection {
        let candidates: [SessionCard]
        switch scope {
        case .all:
            candidates = allCards
        case .category(let deck):
            candidates = CardCategory.cards(allCards, inDeck: deck, includingArchived: true)
        }

        let due = cards(candidates, schedules: schedules, at: date)
        if !due.isEmpty {
            return Selection(cards: due, isAhead: false)
        }

        let ahead = aheadCards(candidates, schedules: schedules, at: date)
        return Selection(cards: ahead, isAhead: !ahead.isEmpty)
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
