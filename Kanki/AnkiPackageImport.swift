import Foundation
import GRDB
import ZIPFoundation

/// Reads content from the genanki container used by the v1 exchange. Anki scheduling is not imported here.
enum AnkiPackageImport {
    enum PackageError: LocalizedError {
        case unsupportedContainer
        case invalidCollection
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .unsupportedContainer: "Выберите пакет .apkg профиля Kanki v1 (collection.anki2)."
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
        let nid: Int64
        let ord: Int
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
            return try AnkiE1Import.prepare(content: readCollection(at: databaseURL), reviewed: nil)
        } catch {
            throw PackageError.invalidCollection
        }
    }

    private static func collection(in archive: Archive) throws -> Entry {
        var collection: Entry?
        for entry in archive {
            switch entry.path {
            case "collection.anki2":
                guard collection == nil, entry.type == .file else { throw PackageError.invalidCollection }
                collection = entry
            case "collection.anki21", "collection.anki21b":
                // Anki can include a legacy placeholder alongside the real modern collection.
                throw PackageError.unsupportedContainer
            default:
                break
            }
        }
        guard let collection else { throw PackageError.unsupportedContainer }
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
            let cards = try SourceCard.fetchAll(db, sql: "SELECT nid, ord FROM main.cards ORDER BY id")
            return try package(models: models, notes: notes, cards: cards)
        }
    }

    private static func package(models: String, notes: [SourceNote], cards: [SourceCard]) throws -> AnkiE1Import.Package {
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
        let sourceCards = try cards.map { card in
            guard let guid = guidByID[card.nid] else { throw PackageError.invalidCollection }
            return AnkiE1Import.Card(guid: guid, ord: card.ord, progress: nil)
        }
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
            try mergeAnkiImport(result.get(), into: destination)
        } catch is AnkiE1Import.ImportError {
            throw AnkiPackageImport.PackageError.invalidCollection
        }
    }
}
