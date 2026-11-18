import Foundation

struct ImportedNoteSummary: Identifiable, Decodable, Equatable, Sendable {
    let uid: String
    let title: String

    var id: String { uid }
}

struct ImportedNoteLink: Identifiable, Equatable, Sendable {
    struct LinkID: Hashable, Sendable {
        let sourceUID: String
        let position: Int
    }

    let id: LinkID
    let uid: String
    let title: String?
    let kind: AnkiE1Import.RelationKind
    let comment: String?
    let isBacklink: Bool

    var type: String { isBacklink ? kind.inverse : kind.rawValue }
}

struct ImportedNote: Equatable, Sendable {
    let summary: ImportedNoteSummary
    let body: String
    let outgoing: [ImportedNoteLink]
    let backlinks: [ImportedNoteLink]

    struct Neighbor: Identifiable, Equatable, Sendable {
        let id: String
        let title: String?
        let outgoing: Bool
        let incoming: Bool
    }

    var neighbors: [Neighbor] {
        let outgoingUIDs = Set(outgoing.map(\.uid))
        let incomingUIDs = Set(backlinks.map(\.uid))
        var seen = Set<String>()
        var result = [Neighbor]()
        for links in [outgoing, backlinks] {
            for link in links where seen.insert(link.uid).inserted {
                result.append(Neighbor(
                    id: link.uid,
                    title: link.title,
                    outgoing: outgoingUIDs.contains(link.uid),
                    incoming: incomingUIDs.contains(link.uid)
                ))
            }
        }
        return result
    }
}
