import SwiftUI

/// Тема приложения. Единственная настройка, которая сохраняется между запусками
/// (ключ `appearance` в `@AppStorage`).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Системное"
        case .light: "Светлое"
        case .dark: "Тёмное"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
