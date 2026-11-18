import Foundation

/// Очередь и режим фиксируются в момент нажатия, а не при построении sheet.
struct ReviewAttempt: Identifiable {
    let id = UUID()
    let cards: [SessionCard]
    let isAhead: Bool
    var title: String?
}
