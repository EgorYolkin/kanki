import Foundation

/// Локальный снимок демо-данных: карточки и их оценки.
/// Кодируется в JSON `LocalCardStore`; серверного источника пока нет.
struct LearningSnapshot: Codable, Equatable {
    var cards: [SessionCard] = []
    var reviews: [SessionReview] = []
}
