import Foundation

/// Очередь отправки снимка: один пуш в полёте, правка во время полёта
/// не отменяет запрос, а требует повтор после завершения.
///
/// Отмена летящего PUT опасна: сервер мог применить запись и поднять
/// ревизию, а клиент об этом не узнает — следующий пуш со старой базой
/// получит ложный 409 и «разрешение» через загрузку с сервера сотрёт правку.
struct PushGate: Equatable {
    private(set) var isRunning = false
    private(set) var needsAnother = false

    /// `true` — вызывающий может отправлять; `false` — запрос уже в полёте,
    /// повтор будет запрошен через `finishAndNeedsAnother()`.
    mutating func begin() -> Bool {
        if isRunning {
            needsAnother = true
            return false
        }
        isRunning = true
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
