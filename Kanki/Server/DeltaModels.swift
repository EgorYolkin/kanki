import Foundation

struct DeltaCursor: Equatable {
    static let start = Self(seq: 0, anchor: nil)

    let seq: Int64
    let anchor: UUID?
}

struct DeltaPage: Decodable {
    struct Change: Decodable {
        let seq: Int64
        let anchor: UUID
        let event: DeltaEvent
    }

    let stream: UUID
    let changes: [Change]
    let more: Bool
}

enum DeltaKind: String, Codable {
    case publication, review, progress
}

struct DeltaReview: Codable, Equatable {
    let kind: DeltaKind
    let id: String
    let uid: String
    let guid: String
    let ord: Int
    let reviewedAt: Double
    let rating: RecallRating
}

struct DeltaProgress: Codable, Equatable {
    let kind: DeltaKind
    let id: String
    let uid: String
    let guid: String
    let ord: Int
    let progress: AnkiE1Import.Progress
}

enum DeltaEvent: Decodable {
    case publication(AnkiE1Import.SourceNote)
    case review(DeltaReview)
    case progress(DeltaProgress)

    private enum CodingKeys: String, CodingKey { case kind, note }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(DeltaKind.self, forKey: .kind) {
        case .publication: self = try .publication(container.decode(AnkiE1Import.SourceNote.self, forKey: .note))
        case .review: self = try .review(DeltaReview(from: decoder))
        case .progress: self = try .progress(DeltaProgress(from: decoder))
        }
    }
}

enum DeltaIdentity {
    static func isValidUID(_ uid: String) -> Bool {
        uid.wholeMatch(of: #/n-[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/#) != nil
    }
}

struct DeltaBatch {
    static let byteLimit = 1_048_576
    static let eventLimit = 50

    private(set) var body: Data
    private(set) var ids: [String] = []
    private let eventLimit: Int

    init(stream: UUID, cursor: DeltaCursor, eventLimit: Int) {
        let anchor = cursor.anchor.map { ",\"anchor\":\"\($0.uuidString.lowercased())\"" } ?? ""
        body = Data("{\"stream\":\"\(stream.uuidString.lowercased())\",\"since\":\(cursor.seq)\(anchor),\"events\":[".utf8)
        self.eventLimit = eventLimit
    }

    mutating func append(_ event: Data, id: String) -> Bool {
        let separatorBytes = ids.isEmpty ? 0 : 1
        guard ids.count < eventLimit, body.count + separatorBytes + event.count + 2 <= Self.byteLimit else { return false }

        if !ids.isEmpty { body.append(0x2c) }
        body.append(event)
        ids.append(id)
        return true
    }

    mutating func finish() {
        body.append(contentsOf: [0x5d, 0x7d])
    }
}

struct DeltaAcknowledgement: Decodable {
    let accepted: [String]
}

enum DeltaError: LocalizedError {
    case requiresHTTPS
    case wrongStream
    case unverifiedCursor
    case invalidPage
    case invalidAcknowledgement
    case eventCollision
    case serverConflict

    var errorDescription: String? {
        switch self {
        case .requiresHTTPS: "Для обмена карточками нужен HTTPS."
        case .wrongStream: "База сервера отличается от подключённой ранее. Журнал оставлен на устройстве."
        case .unverifiedCursor: "Курсор записан без отпечатка истории. Автоматическое восстановление отключено; журнал сохранён."
        case .invalidPage: "Нарушен порядок изменений. Загрузка остановлена."
        case .invalidAcknowledgement: "Сервер не подтвердил журнал. События остались в очереди."
        case .eventCollision: "Один идентификатор соответствует разным событиям. Обмен остановлен."
        case .serverConflict: "Сервер отклонил курсор или событие. Локальный журнал сохранён."
        }
    }
}
