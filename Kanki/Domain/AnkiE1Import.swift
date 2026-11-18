import Foundation

/// Узкий вход Э1, не публичный формат обмена и не модель планировщика Kanki.
struct AnkiE1Import: Equatable {
    struct Note: Codable, Equatable {
        let uid: String
        let guid: String
        let modelID: Int64
        let schemaVersion: Int
        let mod: Int64
        let title: String
        let body: String
        let question: String
        let answer: String
        let sources: String
        let relations: [Relation]
    }

    enum RelationKind: String, Codable {
        case requires
        case partOf = "part_of"
        case related
        case contrast

        var inverse: String {
            switch self {
            case .requires: "required_for"
            case .partOf: "has_part"
            case .related, .contrast: rawValue
            }
        }
    }

    struct Relation: Codable, Equatable {
        let kind: RelationKind
        let targetUID: String
        let note: String?
    }

    struct Edge: Equatable {
        let sourceUID: String
        let type: String
        let targetUID: String
        let sequence: Int
        let derived: Bool
    }

    struct CardKey: Hashable {
        let guid: String
        let ord: Int
    }

    struct Card: Codable, Equatable {
        let guid: String
        let ord: Int
        let progress: Progress?

        var key: CardKey { CardKey(guid: guid, ord: ord) }
    }

    struct Review: Codable, Equatable {
        let id: Int64
        let ease: Int
        let ivl: Int
        let lastIvl: Int
        let factor: Int
        let time: Int
        let type: Int
    }

    /// Сырые числа Anki: due зависит от queue, отрицательный ivl в revlog — секунды.
    struct Progress: Codable, Equatable {
        let due: Int64
        let ivl: Int
        let queue: Int
        let reviews: [Review]
    }

    struct Package: Codable {
        let notes: [SourceNote]
        let models: [String: [String]]
        let cards: [Card]
    }

    struct SourceNote: Codable {
        let guid: String
        let modelID: Int64
        let mod: Int64
        let fields: [String]
    }

    private struct SourceRelation: Decodable {
        let t: RelationKind
        let to: String
        let note: String?
    }

    enum ImportError: Error, Equatable {
        case unsupportedNoteType(Int64)
        case unsupportedFieldLayout
        case unsupportedSchemaVersion(Int)
        case invalidNoteIdentity(String)
        case invalidCardIdentity(CardKey)
        case mismatchedProgress
        case conflictingContent(String)
        case conflictingProgress(CardKey)
    }

    let notes: [Note]
    let cards: [Card]

    var edges: [Edge] {
        var result = [Edge]()
        for note in notes {
            for (sequence, relation) in note.relations.enumerated() {
                result.append(Edge(
                    sourceUID: note.uid,
                    type: relation.kind.rawValue,
                    targetUID: relation.targetUID,
                    sequence: sequence,
                    derived: false
                ))
                result.append(Edge(
                    sourceUID: relation.targetUID,
                    type: relation.kind.inverse,
                    targetUID: note.uid,
                    sequence: sequence,
                    derived: true
                ))
            }
        }
        return result
    }

    static func prepare(content: Package, reviewed: Package?) throws -> Self {
        let notes = try unpack(content)
        let contentNotes = try index(notes)
        let contentCards = try index(content.cards, notes: contentNotes, hasProgress: false)
        guard let reviewed else { return Self(notes: notes, cards: content.cards) }

        let reviewedNotes = try index(unpack(reviewed))
        let reviewedCards = try index(reviewed.cards, notes: reviewedNotes, hasProgress: true)
        guard contentNotes.count == reviewedNotes.count, contentCards.count == reviewedCards.count,
              contentNotes.allSatisfy({ guid, note in reviewedNotes[guid]?.uid == note.uid }),
              contentCards.keys.allSatisfy({ reviewedCards[$0] != nil }) else {
            throw ImportError.mismatchedProgress
        }
        return Self(notes: notes, cards: reviewed.cards)
    }

    static func shouldUpdate(_ note: Note, replacing current: Note) throws -> Bool {
        guard note.guid == current.guid, note.modelID == current.modelID,
              note.schemaVersion == current.schemaVersion else {
            throw ImportError.invalidNoteIdentity(note.uid)
        }
        if note.mod == current.mod, note != current {
            throw ImportError.conflictingContent(note.uid)
        }
        return note.mod > current.mod
    }

    static func shouldUpdate(_ card: Card, replacing current: Card) throws -> Bool {
        guard let incoming = card.progress else { return false }
        guard let stored = current.progress else { return true }
        guard incoming == stored else { throw ImportError.conflictingProgress(card.key) }
        return false
    }

    private static func unpack(_ package: Package) throws -> [Note] {
        let fields = ["UID", "Title", "Body", "Question", "Answer", "Relations", "Sources", "SchemaVersion"]
        let decoder = JSONDecoder()
        return try package.notes.map { source in
            guard source.modelID == 1_936_480_171 else { throw ImportError.unsupportedNoteType(source.modelID) }
            guard package.models[String(source.modelID)] == fields, source.fields.count == fields.count,
                  let schemaVersion = Int(source.fields[7]) else {
                throw ImportError.unsupportedFieldLayout
            }
            guard schemaVersion == 1 else { throw ImportError.unsupportedSchemaVersion(schemaVersion) }
            let relations = try source.fields[5].split(whereSeparator: \.isNewline).map { line in
                let row = try decoder.decode(SourceRelation.self, from: Data(line.utf8))
                return Relation(kind: row.t, targetUID: row.to, note: row.note)
            }
            return Note(
                uid: source.fields[0],
                guid: source.guid,
                modelID: source.modelID,
                schemaVersion: schemaVersion,
                mod: source.mod,
                title: source.fields[1],
                body: source.fields[2],
                question: source.fields[3],
                answer: source.fields[4],
                sources: source.fields[6],
                relations: relations
            )
        }
    }

    private static func index(_ notes: [Note]) throws -> [String: Note] {
        var byGUID = [String: Note](minimumCapacity: notes.count)
        var uids = Set<String>(minimumCapacity: notes.count)
        for note in notes {
            guard note.uid.hasPrefix("n-"), !note.guid.isEmpty,
                  note.relations.allSatisfy({ $0.targetUID.hasPrefix("n-") }),
                  uids.insert(note.uid).inserted, byGUID.updateValue(note, forKey: note.guid) == nil else {
                throw ImportError.invalidNoteIdentity(note.uid)
            }
        }
        return byGUID
    }

    private static func index(_ cards: [Card], notes: [String: Note], hasProgress: Bool) throws -> [CardKey: Card] {
        var byKey = [CardKey: Card](minimumCapacity: cards.count)
        var reviewIDs = Set<Int64>()
        for card in cards {
            guard card.ord == 0, notes[card.guid] != nil, (card.progress != nil) == hasProgress,
                  byKey.updateValue(card, forKey: card.key) == nil else {
                throw ImportError.invalidCardIdentity(card.key)
            }
            if let progress = card.progress {
                for review in progress.reviews where !reviewIDs.insert(review.id).inserted {
                    throw ImportError.invalidCardIdentity(card.key)
                }
            }
        }
        guard byKey.count == notes.count, !notes.isEmpty else { throw ImportError.mismatchedProgress }
        return byKey
    }
}
