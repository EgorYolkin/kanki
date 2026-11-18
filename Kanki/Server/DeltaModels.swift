import Foundation

struct DeltaPage: Decodable {
    struct Change: Decodable {
        let seq: Int64
        let event: DeltaEvent
    }

    let stream: UUID
    let changes: [Change]
    let more: Bool
}

enum DeltaKind: String, Codable {
    case publication, review, progress
}

struct DeltaReview: Codable, Equatable, FetchableDeltaEvent {
    let kind: DeltaKind
    let id: String
    let guid: String
    let ord: Int
    let reviewedAt: Double
    let rating: RecallRating
}

struct DeltaProgress: Codable, Equatable, FetchableDeltaEvent {
    let kind: DeltaKind
    let id: String
    let guid: String
    let ord: Int
    let progress: AnkiE1Import.Progress
}

protocol FetchableDeltaEvent: Encodable, Sendable {
    var id: String { get }
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

struct DeltaWrite: Encodable, Sendable {
    let stream: String
    let events: [any FetchableDeltaEvent]

    private enum CodingKeys: String, CodingKey { case stream, events }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stream, forKey: .stream)
        var rows = container.nestedUnkeyedContainer(forKey: .events)
        for event in events {
            try event.encode(to: rows.superEncoder())
        }
    }
}

struct DeltaAcknowledgement: Decodable {
    let accepted: [String]
}

enum DeltaError: LocalizedError {
    case requiresHTTPS
    case wrongStream
    case invalidPage
    case invalidAcknowledgement
    case eventCollision
    case serverConflict

    var errorDescription: String? {
        switch self {
        case .requiresHTTPS: "Для обмена карточками нужен HTTPS."
        case .wrongStream: "База сервера отличается от подключённой ранее. Журнал оставлен на устройстве."
        case .invalidPage: "Нарушен порядок изменений. Загрузка остановлена."
        case .invalidAcknowledgement: "Сервер не подтвердил журнал. События остались в очереди."
        case .eventCollision: "Один идентификатор соответствует разным событиям. Обмен остановлен."
        case .serverConflict: "Сервер отклонил курсор или событие. Локальный журнал сохранён."
        }
    }
}
