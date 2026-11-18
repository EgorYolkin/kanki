/// Ошибка чтения запрещает обмен. Даже после восстановления ответ PUT,
/// отправленного до ошибки, не подтверждает ревизию восстановленного снимка.
struct SnapshotReadState {
    private(set) var failure: String?
    private(set) var generation = 0

    init(failure: String? = nil) {
        self.failure = failure
    }

    var isReadable: Bool { failure == nil }

    mutating func didFail(_ message: String) {
        generation += 1
        failure = message
    }

    mutating func didLoad() {
        failure = nil
    }

    func acceptsResult(from generation: Int) -> Bool {
        isReadable && self.generation == generation
    }
}
