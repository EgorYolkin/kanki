import Foundation

/// Explicit sync for imported cards, independent of the legacy snapshot client.
enum ImportedDeltaSync {
    struct Result {
        let pulled: Int
        let pushed: Int
        let progressConflicts: Int
        let publicationConflicts: Int
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
        let client = ServerClient(configuration: configuration, token: token, session: session)
        var cursor = try LocalCardStore.deltaCursor(from: store)
        var page = try await client.fetchDelta(since: cursor)
        try LocalCardStore.bindDeltaStream(page.stream, in: store)
        // A conflicting publication must not keep this device's offline journal from reaching the server.
        let pushed = try await push(client: client, stream: page.stream, store: store)
        if page.changes.isEmpty, pushed > 0 {
            page = try await client.fetchDelta(since: cursor)
        }

        var pulled = 0
        while true {
            pulled += try LocalCardStore.applyDeltaPage(page, since: cursor, in: store)
            guard page.more else { break }
            guard let next = page.changes.last?.seq else { throw DeltaError.invalidPage }
            cursor = next
            page = try await client.fetchDelta(since: cursor)
        }
        let conflicts = try LocalCardStore.deltaConflicts(from: store)
        return Result(pulled: pulled, pushed: pushed, progressConflicts: conflicts.progress, publicationConflicts: conflicts.publications)
    }

    private static func push(client: ServerClient, stream: UUID, store: URL) async throws -> Int {
        var count = 0
        while true {
            let events = try LocalCardStore.pendingDeltaEvents(from: store)
            guard !events.isEmpty else { return count }

            let response = try await client.pushDelta(.init(stream: stream.uuidString.lowercased(), events: events))
            guard response.accepted == events.map(\.id) else { throw DeltaError.invalidAcknowledgement }

            try LocalCardStore.acknowledgeDeltaEvents(response.accepted, in: store)
            count += events.count
        }
    }
}

extension Notification.Name {
    static let kankiImportedCardsChanged = Notification.Name("kanki.importedCardsChanged")
}
