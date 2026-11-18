import Foundation
import GRDB
import ZIPFoundation

/// Reads the legacy SQLite container used by v1, including raw Anki progress when present.
enum AnkiPackageImport {
    enum PackageError: LocalizedError {
        case unsupportedContainer
        case invalidCollection
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .unsupportedContainer: "Выберите пакет .apkg профиля Kanki v1 в режиме совместимости."
            case .invalidCollection: "Пакет повреждён или не соответствует профилю Kanki v1."
            case .tooLarge: "База внутри пакета превышает 32 МиБ."
            }
        }
    }

    private struct ModelField: Decodable {
        let name: String
        let ord: Int
    }

    private struct ModelTemplate: Decodable {
        let ord: Int
    }

    private struct Model: Decodable {
        let flds: [ModelField]
        let tmpls: [ModelTemplate]
    }

    private struct SourceNote: FetchableRecord, Decodable {
        let id: Int64
        let guid: String
        let mid: Int64
        let mod: Int64
        let flds: String
    }

    private struct SourceCard: FetchableRecord, Decodable {
        let id: Int64
        let nid: Int64
        let ord: Int
        let due: Int64
        let ivl: Int
        let queue: Int
    }

    private struct SourceReview: FetchableRecord, Decodable {
        let cid: Int64
        let id: Int64
        let ease: Int
        let ivl: Int
        let lastIvl: Int
        let factor: Int
        let time: Int
        let type: Int

        var value: AnkiE1Import.Review {
            .init(id: id, ease: ease, ivl: ivl, lastIvl: lastIvl, factor: factor, time: time, type: type)
        }
    }

    private static let maximumCollectionSize = 32 * 1_024 * 1_024

    static func read(at url: URL) throws -> AnkiE1Import {
        guard url.pathExtension.lowercased() == "apkg" else { throw PackageError.unsupportedContainer }
        guard let archive = try? Archive(url: url, accessMode: .read, pathEncoding: nil) else { throw PackageError.invalidCollection }
        let entry = try collection(in: archive)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appending(path: "collection.sqlite")
        try extract(entry, from: archive, to: databaseURL)
        do {
            return try AnkiE1Import.prepareImportedPackage(readCollection(at: databaseURL))
        } catch {
            throw PackageError.invalidCollection
        }
    }

    private static func collection(in archive: Archive) throws -> Entry {
        var legacy: Entry?
        var compatible: Entry?
        for entry in archive {
            switch entry.path {
            case "collection.anki2":
                guard legacy == nil, entry.type == .file else { throw PackageError.invalidCollection }
                legacy = entry
            case "collection.anki21":
                guard compatible == nil, entry.type == .file else { throw PackageError.invalidCollection }
                compatible = entry
            case "collection.anki21b":
                // Never import the legacy placeholder of a compressed modern package.
                throw PackageError.unsupportedContainer
            default:
                break
            }
        }
        guard let collection = compatible ?? legacy else { throw PackageError.unsupportedContainer }
        guard collection.uncompressedSize <= maximumCollectionSize else { throw PackageError.tooLarge }
        return collection
    }

    private static func extract(_ entry: Entry, from archive: Archive, to url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        var written = 0
        let checksum = try archive.extract(entry) { chunk in
            guard chunk.count <= maximumCollectionSize - written else { throw PackageError.tooLarge }
            try file.write(contentsOf: chunk)
            written += chunk.count
        }
        guard written == entry.uncompressedSize, checksum == entry.checksum else {
            throw PackageError.invalidCollection
        }
    }

    private static func readCollection(at url: URL) throws -> AnkiE1Import.Package {
        var configuration = Configuration()
        configuration.readonly = true
        let source = try DatabaseQueue(path: url.path, configuration: configuration)
        return try source.read { db in
            try db.execute(sql: "PRAGMA trusted_schema = OFF")
            let tables = try Row.fetchAll(db, sql: "PRAGMA main.table_list")
            for name in ["col", "notes", "cards"] where !tables.contains(where: { $0["name"] == name && $0["type"] == "table" }) {
                throw PackageError.invalidCollection
            }
            guard let models = try String.fetchOne(db, sql: "SELECT models FROM main.col") else {
                throw PackageError.invalidCollection
            }
            let notes = try SourceNote.fetchAll(db, sql: "SELECT id, guid, mid, mod, flds FROM main.notes ORDER BY id")
            let cards = try SourceCard.fetchAll(db, sql: "SELECT id, nid, ord, due, ivl, queue FROM main.cards ORDER BY id")
            guard tables.contains(where: { $0["name"] == "revlog" && $0["type"] == "table" }) else {
                throw PackageError.invalidCollection
            }
            let log = try SourceReview.fetchAll(db, sql: "SELECT cid, id, ease, ivl, lastIvl, factor, time, type FROM main.revlog ORDER BY id")
            return try package(models: models, notes: notes, cards: cards, reviews: log)
        }
    }

    private static func package(
        models: String,
        notes: [SourceNote],
        cards: [SourceCard],
        reviews: [SourceReview]
    ) throws -> AnkiE1Import.Package {
        let models = try JSONDecoder().decode([String: Model].self, from: Data(models.utf8))
        var fields = [String: [String]]()
        var guidByID = [Int64: String](minimumCapacity: notes.count)
        let sourceNotes = try notes.map { note in
            let key = String(note.mid)
            if fields[key] == nil {
                guard let model = models[key], model.tmpls.map(\.ord) == [0] else { throw PackageError.invalidCollection }
                let orderedFields = model.flds.sorted { $0.ord < $1.ord }
                guard orderedFields.map(\.ord).elementsEqual(orderedFields.indices) else { throw PackageError.invalidCollection }
                fields[key] = orderedFields.map(\.name)
            }
            guard guidByID.updateValue(note.guid, forKey: note.id) == nil else { throw PackageError.invalidCollection }
            return AnkiE1Import.SourceNote(
                guid: note.guid,
                modelID: note.mid,
                mod: note.mod,
                fields: note.flds.components(separatedBy: "\u{1f}")
            )
        }
        var byCard = Dictionary(grouping: reviews, by: \.cid)
        let sourceCards = try cards.map { card in
            guard let guid = guidByID[card.nid] else { throw PackageError.invalidCollection }
            let log = byCard.removeValue(forKey: card.id)?.map(\.value) ?? []
            let progress: AnkiE1Import.Progress? = card.queue == 0 && card.ivl == 0 && log.isEmpty
                ? nil : .init(due: card.due, ivl: card.ivl, queue: card.queue, reviews: log)
            return AnkiE1Import.Card(guid: guid, ord: card.ord, progress: progress)
        }
        guard byCard.isEmpty else { throw PackageError.invalidCollection }
        return .init(notes: sourceNotes, models: fields, cards: sourceCards)
    }
}

extension LocalCardStore {
    static func importAnkiPackage(at url: URL, into destination: URL = fileURL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var error: NSError?
        var result: Result<AnkiE1Import, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { coordinatedURL in
            result = Result { try AnkiPackageImport.read(at: coordinatedURL) }
        }
        if let error { throw error }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        do {
            try mergeAnkiImport(result.get(), into: destination, preserveProgressConflicts: true)
        } catch is AnkiE1Import.ImportError {
            throw AnkiPackageImport.PackageError.invalidCollection
        }
    }
}
