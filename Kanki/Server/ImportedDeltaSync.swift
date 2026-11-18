import Foundation

/// Explicit sync for imported cards, independent of the legacy snapshot client.
enum ImportedDeltaSync {
    struct Result {
        var pulled = 0
        var pushed = 0
        var pullError: Error?
        var pushError: Error?
        var progressConflicts = 0
        var publicationConflicts = 0
        var quarantined = 0
    }

    static func run(
        configuration: ServerConfiguration,
        token: String,
        pin: String,
        store: URL = LocalCardStore.fileURL
    ) async throws -> Result {
        guard configuration.baseURL.scheme?.lowercased() == "https" else { throw DeltaError.requiresHTTPS }

        let session = try DeltaTransport.session(pin: pin)
        defer { session.finishTasksAndInvalidate() }
        return try await run(client: ServerClient(configuration: configuration, token: token, session: session), store: store)
    }

    static func run(client: ServerClient, store: URL) async throws -> Result {
        var cursor = try LocalCardStore.deltaCursor(from: store)
        var page = try await client.fetchDelta(since: cursor)
        let stream = page.stream
        try LocalCardStore.bindDeltaStream(stream, in: store)

        var result = Result()
        do {
            try apply(page, cursor: &cursor, pulled: &result.pulled, store: store)
        } catch {
            result.pullError = error
        }
        do {
            try await push(client: client, stream: stream, cursor: cursor, count: &result.pushed, store: store)
        } catch {
            result.pushError = error
        }
        do {
            if result.pullError == nil, page.more || (page.changes.isEmpty && result.pushed > 0) {
                repeat {
                    page = try await client.fetchDelta(since: cursor)
                    try apply(page, cursor: &cursor, pulled: &result.pulled, store: store)
                } while page.more
            }
            let conflicts = try LocalCardStore.deltaConflicts(from: store)
            result.progressConflicts = conflicts.progress
            result.publicationConflicts = conflicts.publications
            result.quarantined = conflicts.quarantined
        } catch {
            result.pullError = result.pullError ?? error
        }
        return result
    }

    private static func apply(_ page: DeltaPage, cursor: inout DeltaCursor, pulled: inout Int, store: URL) throws {
        pulled += try LocalCardStore.applyDeltaPage(page, since: cursor, in: store)
        if let last = page.changes.last {
            cursor = DeltaCursor(seq: last.seq, anchor: last.anchor)
        }
    }

    private static func push(
        client: ServerClient, stream: UUID, cursor: DeltaCursor, count: inout Int, store: URL
    ) async throws {
        var eventLimit = DeltaBatch.eventLimit
        while true {
            let batch = try LocalCardStore.nextDeltaBatch(stream: stream, cursor: cursor, eventLimit: eventLimit, from: store)
            guard !batch.ids.isEmpty else { return }

            do {
                let response = try await client.pushDelta(batch.body)
                guard response.accepted == batch.ids else { throw DeltaError.invalidAcknowledgement }

                try LocalCardStore.acknowledgeDeltaEvents(response.accepted, in: store)
                count += batch.ids.count
            } catch ServerError.http(let status) where status == 413 {
                if batch.ids.count == 1, let id = batch.ids.first {
                    try LocalCardStore.quarantineDeltaEvent(id, in: store)
                } else {
                    eventLimit = batch.ids.count / 2
                }
            }
        }
    }
}

extension Notification.Name {
    static let kankiImportedCardsChanged = Notification.Name("kanki.importedCardsChanged")
}
