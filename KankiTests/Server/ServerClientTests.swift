import XCTest
@testable import Kanki

private class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    static func install(
        _ handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) {
        self.handler = handler
        lastRequest = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: ServerError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func bodyData(from request: URLRequest) throws -> Data {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        throw ServerError.invalidResponse
    }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4_096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
        let read = buffer.withUnsafeMutableBytes { bytes -> Int in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return stream.read(base, maxLength: bufferSize)
        }
        if read < 0 {
            throw stream.streamError ?? ServerError.invalidResponse
        }
        if read == 0 {
            break
        }
        data.append(buffer, count: read)
    }
    return data
}

private func makeResponse(_ status: Int, _ request: URLRequest) throws -> HTTPURLResponse {
    let url = try XCTUnwrap(request.url)
    return try XCTUnwrap(
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
    )
}

final class ServerClientTests: XCTestCase {
    func testDeltaPersistsPullWhenPostIsUnavailableRejectedOrPartiallyAcknowledged() async throws {
        for status in [503, 409, 200] {
            let store = try deltaFixtureStore()
            defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
            try seedOfflineDeltaReviews(in: store)
            let pending = try deltaFixtureBatch(from: store).ids
            let partial = try JSONEncoder().encode(["accepted": Array(pending.prefix(1))])
            StubURLProtocol.install { request in
                if request.httpMethod == "GET" {
                    return (try makeResponse(200, request), Self.deltaFixturePage)
                }
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData(from: request)) as? [String: Any])
                XCTAssertEqual(body["since"] as? Int, 1)
                XCTAssertEqual(body["anchor"] as? String, "10000000-0000-4000-8000-000000000001")
                return (try makeResponse(status, request), partial)
            }
            let result = try await ImportedDeltaSync.run(client: makeClient(), store: store)
            XCTAssertEqual(result.pulled, 1)
            XCTAssertNil(result.pullError)
            XCTAssertNotNil(result.pushError)
            XCTAssertEqual(result.pushed, 0)
            XCTAssertEqual(try LocalCardStore.deltaCursor(from: store).seq, 1)
            XCTAssertTrue(try LocalCardStore.importedCards(from: store).contains { $0.title == "Из сети" })
            XCTAssertEqual(try deltaFixtureBatch(from: store).ids, pending)
        }
    }

    func testDeltaSplitsOn413AndKeepsRejectedSingletonWithoutBlockingOtherReviews() async throws {
        let store = try deltaFixtureStore()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        try seedOfflineDeltaReviews(in: store)
        let ids = try deltaFixtureBatch(from: store).ids
        let rejected = try XCTUnwrap(ids.first)
        StubURLProtocol.install { request in
            if request.httpMethod == "GET" {
                return (try makeResponse(200, request), Self.deltaFixturePage)
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData(from: request)) as? [String: Any])
            let events = try XCTUnwrap(body["events"] as? [[String: Any]])
            let sent = events.compactMap { $0["id"] as? String }
            if sent.count > 1 || sent == [rejected] {
                return (try makeResponse(413, request), Data())
            }
            return (try makeResponse(200, request), try JSONEncoder().encode(["accepted": sent]))
        }
        let result = try await ImportedDeltaSync.run(client: makeClient(), store: store)
        XCTAssertEqual(result.pushed, 1)
        XCTAssertNil(result.pushError)
        XCTAssertEqual(result.quarantined, 1)
        XCTAssertTrue(try deltaFixtureBatch(from: store).ids.isEmpty)
        let card = try LocalCardStore.importedCard(.init(guid: "offline", ord: 0), from: store)
        XCTAssertEqual(card.reviews.map(\.rating), [.good, .hard])
    }

    private static let deltaFixturePage = Data("""
        {"stream":"00000000-0000-4000-8000-000000000042","more":false,
         "changes":[{"seq":1,"anchor":"10000000-0000-4000-8000-000000000001",
          "event":{"kind":"publication","note":{"guid":"online","modelID":\(AnkiE1Import.modelID),"mod":1,
          "fields":["n-018f3a2b-7c41-7000-8000-000000000002","Из сети","","","","","","1"]}}}]}
        """.utf8)

    private func deltaFixtureStore() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "cards.sqlite")
    }

    private func seedOfflineDeltaReviews(in store: URL) throws {
        let key = AnkiE1Import.CardKey(guid: "offline", ord: 0)
        let note = AnkiE1Import.SourceNote(
            guid: key.guid,
            modelID: AnkiE1Import.modelID,
            mod: 1,
            fields: ["n-018f3a2b-7c41-7000-8000-000000000001", "Офлайн", "", "", "", "", "", "1"]
        )
        try LocalCardStore.mergeAnkiImport(AnkiE1Import.preparePublication(note), into: store)
        let card = try LocalCardStore.importedCard(key, from: store)
        let first = try LocalCardStore.recordImportedReview(key, shown: card, rating: .hard, at: .init(timeIntervalSince1970: 1_800_000_000), in: store)
        let due = try XCTUnwrap(first.schedule?.due)
        _ = try LocalCardStore.recordImportedReview(key, shown: first, rating: .good, at: due, in: store)
    }

    private func deltaFixtureBatch(from store: URL) throws -> DeltaBatch {
        try LocalCardStore.nextDeltaBatch(
            stream: UUID(), cursor: LocalCardStore.deltaCursor(from: store), eventLimit: DeltaBatch.eventLimit, from: store
        )
    }

    func testIdentitySendsBearerToken() async throws {
        StubURLProtocol.install { request in
            StubURLProtocol.lastRequest = request
            return (
                try makeResponse(200, request),
                Data(#"{"label":"iphone","role":"device"}"#.utf8)
            )
        }

        let identity = try await makeClient().identity()

        XCTAssertEqual(identity, ServerIdentity(label: "iphone", role: "device"))
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/v1/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testFetchesEmptySnapshot() async throws {
        StubURLProtocol.install { request in
            (
                try makeResponse(200, request),
                Data(#"{"revision":0,"schema_version":1,"data":null,"updated_at":null}"#.utf8)
            )
        }

        let snapshot = try await makeClient().fetchSnapshot()

        XCTAssertEqual(snapshot.revision, 0)
        XCTAssertNil(snapshot.data)
    }

    func testPushSendsBaseRevisionAndDecodesResult() async throws {
        let response = """
        {"revision":3,"schema_version":1,"updated_at":"2026-01-01T00:00:00Z",
         "data":{"cards":[],"reviews":[]}}
        """
        StubURLProtocol.install { request in
            StubURLProtocol.lastRequest = request
            return (try makeResponse(200, request), Data(response.utf8))
        }

        let result = try await makeClient().push(
            snapshot: LearningSnapshot(),
            baseRevision: 2
        )

        XCTAssertEqual(result.revision, 3)
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try bodyData(from: request)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        XCTAssertEqual(object["base_revision"] as? Int, 2)
        XCTAssertEqual(object["schema_version"] as? Int, 1)
    }

    func testConflictCarriesCurrentRevision() async throws {
        StubURLProtocol.install { request in
            (
                try makeResponse(409, request),
                Data(#"{"detail":{"code":"revision_conflict","current_revision":5}}"#.utf8)
            )
        }

        do {
            _ = try await makeClient().push(
                snapshot: LearningSnapshot(),
                baseRevision: 2
            )
            XCTFail("Ожидался конфликт")
        } catch {
            XCTAssertEqual(error as? ServerError, .conflict(currentRevision: 5))
        }
    }

    func testUnauthorizedAndServerErrors() async throws {
        StubURLProtocol.install { request in
            (try makeResponse(401, request), Data())
        }
        do {
            _ = try await makeClient().identity()
            XCTFail("Ожидался 401")
        } catch {
            XCTAssertEqual(error as? ServerError, .unauthorized)
        }

        StubURLProtocol.install { request in
            (try makeResponse(500, request), Data())
        }
        do {
            _ = try await makeClient().identity()
            XCTFail("Ожидался 500")
        } catch {
            XCTAssertEqual(error as? ServerError, .http(status: 500))
        }
    }

    func testWireNormalizationMatchesStoredPayload() throws {
        let cardID = UUID()
        let moment = Date(timeIntervalSince1970: 1_770_000_000.123456)
        let snapshot = LearningSnapshot(
            cards: [
                SessionCard(
                    id: cardID,
                    question: "Вопрос",
                    answer: "Ответ",
                    createdAt: moment
                )
            ],
            reviews: [SessionReview(cardID: cardID, rating: .good, reviewedAt: moment)]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Снимок в том виде, в каком его вернёт сервер после нашего PUT.
        let stored = try decoder.decode(
            LearningSnapshot.self,
            from: encoder.encode(snapshot)
        )

        XCTAssertEqual(ServerClient.wireNormalized(snapshot), stored)
        XCTAssertNotEqual(
            stored,
            snapshot,
            "Провод теряет дробные секунды — сравнение обязано это учитывать"
        )
    }

    func testMalformedJSONMapsToDecodingError() async throws {
        StubURLProtocol.install { request in
            (try makeResponse(200, request), Data("not-json".utf8))
        }

        do {
            _ = try await makeClient().identity()
            XCTFail("Ожидалась ошибка декодирования")
        } catch {
            XCTAssertEqual(error as? ServerError, .decoding)
        }
    }

    private func makeClient() throws -> ServerClient {
        let configuration = try XCTUnwrap(
            ServerConfiguration(rawValue: "http://127.0.0.1:8000")
        )
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubURLProtocol.self]
        return ServerClient(
            configuration: configuration,
            token: "secret",
            session: URLSession(configuration: sessionConfiguration)
        )
    }
}
