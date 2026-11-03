import Foundation

/// Локальный журнал записей экрана «Конфликты»: потери категорий при загрузке
/// снапшота и тексты конфликтов ревизий. Хранится в UserDefaults.
enum ConflictLog {
    private static let key = "conflictLog"

    static func entries() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func append(_ newEntries: [String]) {
        guard !newEntries.isEmpty else { return }
        var all = entries()
        all.append(contentsOf: newEntries)
        UserDefaults.standard.set(all, forKey: key)
        NotificationCenter.default.post(name: .kankiConflictLogUpdated, object: nil)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: .kankiConflictLogUpdated, object: nil)
    }
}

extension Notification.Name {
    static let kankiConflictLogUpdated = Notification.Name("kanki.conflictLogUpdated")
}
