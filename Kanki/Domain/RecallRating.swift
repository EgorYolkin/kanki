import SwiftUI

/// Оценка ответа в демо-сеансе. Значения `rawValue` 1–4 совпадают с порядком
/// кнопок «Снова / Трудно / Хорошо / Легко».
enum RecallRating: Int, CaseIterable {
    case again = 1
    case hard
    case good
    case easy

    var title: String {
        switch self {
        case .again: "Снова"
        case .hard: "Трудно"
        case .good: "Хорошо"
        case .easy: "Легко"
        }
    }

    var tint: Color {
        switch self {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }
}
