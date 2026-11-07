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
