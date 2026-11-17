import Foundation

/// Один авто-push или ручная синхронизация в полёте. Поколение правок
/// защищает подтверждения PUT и ответы GET от изменений за время ожидания.
///
/// Отмена летящего PUT опасна: сервер мог применить запись и поднять
/// ревизию, а клиент об этом не узнает — следующий пуш со старой базой
/// получит ложный 409 и «разрешение» через загрузку с сервера сотрёт правку.
struct PushGate: Equatable {
    private(set) var isRunning = false
    private(set) var needsAnother = false
    private(set) var isManualSyncRunning = false
    private(set) var generation = 0

    /// Любая сохранённая правка инвалидирует ответы, начатые до неё,
    /// даже если пользователь затем вернул прежнее содержимое.
    mutating func markChanged() {
        generation += 1
        if isRunning {
            needsAnother = true
        }
    }

    func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation
    }

    func canApplyFetch(startedAt generation: Int) -> Bool {
        isCurrent(generation) && !isRunning && !isManualSyncRunning
    }

    mutating func beginManualSync() -> Bool {
        guard !isRunning, !isManualSyncRunning else { return false }
        isManualSyncRunning = true
        generation += 1
        return true
    }

    mutating func finishManualSync() {
        isManualSyncRunning = false
    }

    /// `true` — вызывающий может отправлять; `false` — запрос уже в полёте,
    /// повтор будет запрошен через `finishAndNeedsAnother()`.
    mutating func begin() -> Bool {
        guard !isManualSyncRunning else { return false }
        if isRunning {
            needsAnother = true
            return false
        }
        isRunning = true
        generation += 1
        return true
    }

    /// `true` — за время полёта появилась правка, нужен ещё один пуш;
    /// `false` — очередь пуста, полёт завершён.
    mutating func finishAndNeedsAnother() -> Bool {
        if needsAnother {
            needsAnother = false
            return true
        }
        isRunning = false
        return false
    }
}
