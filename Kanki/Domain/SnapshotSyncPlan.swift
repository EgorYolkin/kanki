import Foundation

/// Решение авто-синхронизации после сверки локального состояния с серверным снимком.
enum SnapshotSyncAction: Equatable {
    /// Ревизии совпадают, несинхронизированных правок нет — делать нечего.
    case noop
    /// Ревизии совпадают, есть несинхронизированные правки — отправить снимок.
    case pushLocal
    /// Сервер ушёл вперёд при чистом локальном состоянии — применить удалённый снимок.
    case applyRemote
    /// Сервер ушёл вперёд, но данные равны локальным — принять ревизию без записи.
    case adoptRevision
    /// Обе стороны менялись независимо — конфликт разрешается вручную в настройках.
    case conflict
}

/// Чистая матрица решений авто-синхронизации: только входы и решение, без I/O.
/// Сервер — источник истины, тихий мерж запрещён: при двустороннем расхождении
/// возвращается `.conflict`, выбор за пользователем.
enum SnapshotSyncPlan {
    static func action(
        localDirty: Bool,
        knownRevision: Int,
        remoteRevision: Int,
        remoteDataEqualsLocal: Bool
    ) -> SnapshotSyncAction {
        if remoteRevision == knownRevision {
            return localDirty ? .pushLocal : .noop
        }
        if localDirty {
            return remoteDataEqualsLocal ? .adoptRevision : .conflict
        }
        return .applyRemote
    }
}
