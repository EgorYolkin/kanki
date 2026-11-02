import Foundation

/// Очередь повторения: новые карточки и те, чей срок уже наступил.
/// Сортировка: сначала меньший due, затем более старые карточки.
enum ReviewQueue {
    static func cards(
        _ cards: [SessionCard],
        schedules: [UUID: CardSchedule],
        at date: Date
    ) -> [SessionCard] {
        cards
            .filter { schedules[$0.id].map { $0.due <= date } ?? true }
            .sorted { lhs, rhs in
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
}
