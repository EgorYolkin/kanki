import Foundation

/// Честный текст статуса синхронизации для экрана «Обучение».
/// Приоритет: конфликт → ошибка синхронизации → неотправленные
/// правки → успешная синхронизация. `nil` — сервер не настроен, строка
/// не показывается: интерфейс не упоминает несуществующую синхронизацию.
enum SyncStatus {
    enum Problem: Equatable {
        case conflict(currentRevision: Int)
        case unauthorized
        case unavailable
        case failed

        init?(error: Error) {
            if error is CancellationError { return nil }
            if let urlError = error as? URLError {
                guard urlError.code != .cancelled else { return nil }
                self = .unavailable
                return
            }
            switch error as? ServerError {
            case .conflict(let revision): self = .conflict(currentRevision: revision)
            case .unauthorized: self = .unauthorized
            case .invalidResponse, .http, .decoding, nil: self = .failed
            }
        }

        var text: String {
            switch self {
            case .conflict: "Конфликт ревизий — разрешите в настройках"
            case .unauthorized: "Токен отклонён — проверьте настройки сервера"
            case .unavailable: "Сервер недоступен — повтор при следующем открытии"
            case .failed: "Не удалось синхронизировать — повтор при следующем открытии"
            }
        }
    }

    // Подтверждённый конфликт остаётся до успешной сверки или обмена.
    static func retainingConflict(_ previous: Problem?, onFailure problem: Problem) -> Problem {
        if case .conflict = problem { return problem }
        if let previous, case .conflict = previous { return previous }
        return problem
    }

    static func text(
        isConfigured: Bool,
        problem: Problem?,
        hasUnsyncedChanges: Bool,
        knownRevision: Int
    ) -> String? {
        guard isConfigured else { return nil }
        if let problem { return problem.text }
        if hasUnsyncedChanges { return "Есть неотправленные изменения" }
        if knownRevision > 0 { return "Синхронизировано, ревизия \(knownRevision)" }
        return "Синхронизация ещё не выполнялась"
    }
}
