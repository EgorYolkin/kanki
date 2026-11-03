import Foundation

/// Честный текст статуса синхронизации для экрана «Обучение».
/// Приоритет: конфликт (нужно действие) → сетевая ошибка → неотправленные
/// правки → успешная синхронизация. `nil` — сервер не настроен, строка
/// не показывается: интерфейс не упоминает несуществующую синхронизацию.
enum SyncStatus {
    static func text(
        isConfigured: Bool,
        hasConflict: Bool,
        lastSyncFailed: Bool,
        hasUnsyncedChanges: Bool,
        knownRevision: Int
    ) -> String? {
        guard isConfigured else { return nil }
        if hasConflict { return "Конфликт ревизий — разрешите в настройках" }
        if lastSyncFailed { return "Сервер недоступен — повтор при следующем открытии" }
        if hasUnsyncedChanges { return "Есть неотправленные изменения" }
        if knownRevision > 0 { return "Синхронизировано, ревизия \(knownRevision)" }
        return "Синхронизация ещё не выполнялась"
    }
}
