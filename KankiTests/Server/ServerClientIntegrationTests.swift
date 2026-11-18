import XCTest
@testable import Kanki

/// Opt-in реальный обмен с запущенным сервером. В CI без переменных окружения тест пропускается.
final class ServerClientIntegrationTests: XCTestCase {
    func testRealServerRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard
            let rawURL = environment["KANKI_TEST_SERVER_URL"],
            let token = environment["KANKI_TEST_TOKEN"],
            !rawURL.isEmpty,
            !token.isEmpty
        else {
            throw XCTSkip("Задайте KANKI_TEST_SERVER_URL и KANKI_TEST_TOKEN")
        }

        let configuration = try XCTUnwrap(ServerConfiguration(rawValue: rawURL))
        guard configuration.baseURL.host == "127.0.0.1" else {
            return XCTFail("Тест заменяет снимок целиком. Используйте одноразовую БД на 127.0.0.1.")
        }
        let client = ServerClient(configuration: configuration, token: token)

        let identity = try await client.identity()
        XCTAssertFalse(identity.label.isEmpty)

        let before = try await client.fetchSnapshot()
        let marker = "integration-\(UUID().uuidString)"
        let local = LearningSnapshot(
            cards: [SessionCard(question: marker, answer: "ok")]
        )
        let written = try await client.push(snapshot: local, baseRevision: before.revision)

        XCTAssertEqual(written.revision, before.revision + 1)
        let fetched = try await client.fetchSnapshot()
        XCTAssertEqual(fetched.revision, written.revision)
        XCTAssertEqual(fetched.data?.cards.first?.question, marker)
        XCTAssertEqual(fetched.data?.snapshotVersion, 3)
        try await exerciseLesson(
            client: client, configuration: configuration, token: token,
            legacy: local, revision: fetched.revision
        )
    }

    private func exerciseLesson(
        client: ServerClient, configuration: ServerConfiguration, token: String,
        legacy: LearningSnapshot, revision: Int
    ) async throws {

        let ids = (0..<12).map { _ in UUID() }
        let lessonID = UUID()
        try await addAgentBatch(configuration: configuration, token: token, ids: ids, lessonID: lessonID)
        let batch = try await client.fetchSnapshot()
        XCTAssertEqual(batch.revision, revision + 1)
        var snapshot = try XCTUnwrap(batch.data)
        XCTAssertEqual(snapshot.snapshotVersion, 4)
        XCTAssertEqual(snapshot.cards.first?.question, legacy.cards.first?.question)
        let cards = snapshot.reviewCards(forLessonID: lessonID)
        XCTAssertEqual(cards.map(\.id), ids)
        for (index, card) in cards.enumerated() {
            XCTAssertEqual(card.question, "Демо \(index)\n**вопрос**")
            XCTAssertEqual(card.answer, #"Литерал \n"# + "\n- Ответ")
        }

        let reviewed = try XCTUnwrap(cards.first)
        try CardScheduling.record(
            reviewed, rating: .good, in: &snapshot, at: Date(timeIntervalSince1970: 1_800_000_000.75)
        )
        // Ответ на PUT не участвует в решении: клиент всё ещё знает ревизию batch.
        _ = try await client.push(snapshot: snapshot, baseRevision: batch.revision)
        do {
            _ = try await client.push(snapshot: legacy, baseRevision: batch.revision)
            XCTFail("Сервер принял устаревшую ревизию")
        } catch let error as ServerError {
            XCTAssertEqual(error, .conflict(currentRevision: batch.revision + 1))
        }
        let remote = try await client.fetchSnapshot()
        XCTAssertEqual(remote.revision, batch.revision + 1)
        let data = try XCTUnwrap(remote.data)
        XCTAssertEqual(data.cards, batch.data?.cards)
        XCTAssertEqual(data.lessons, batch.data?.lessons)
        XCTAssertEqual(data.reviews.map(\.cardID), [reviewed.id])
        XCTAssertEqual(Set(data.schedules.keys), [reviewed.id])
        try assertLostResponse(snapshot, remote: remote, knownRevision: batch.revision)
    }

    private func assertLostResponse(
        _ local: LearningSnapshot, remote: ServerSnapshot, knownRevision: Int
    ) throws {
        func action(_ snapshot: LearningSnapshot) throws -> SnapshotSyncAction {
            let normalized = try XCTUnwrap(ServerClient.wireNormalized(snapshot))
            return SnapshotSyncPlan.action(
                localDirty: true, knownRevision: knownRevision, remoteRevision: remote.revision,
                remoteDataEqualsLocal: normalized == remote.data
            )
        }

        XCTAssertNotEqual(local, remote.data)
        XCTAssertEqual(try action(local), .adoptRevision)
        var changed = local
        let lesson = try XCTUnwrap(local.lessons.first)
        changed.lessons = [Lesson(
            id: lesson.id, title: lesson.title, course: lesson.course, sourceURL: lesson.sourceURL,
            createdAt: lesson.createdAt, cardIDs: Array(lesson.cardIDs.dropLast())
        )]
        XCTAssertEqual(try action(changed), .conflict)
    }

    /// Независимый REST-писатель: меняет полученный JSON, не используя Codable приложения.
    private func addAgentBatch(
        configuration: ServerConfiguration, token: String, ids: [UUID], lessonID: UUID
    ) async throws {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/snapshot"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (body, readResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((readResponse as? HTTPURLResponse)?.statusCode, 200)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let revision = try XCTUnwrap(envelope["revision"] as? Int)
        var data = try XCTUnwrap(envelope["data"] as? [String: Any])
        XCTAssertNil(data["lessons"])
        var cards = try XCTUnwrap(data["cards"] as? [[String: Any]])
        let createdAt = "2026-11-01T12:00:00Z"
        for (index, id) in ids.enumerated() {
            cards.append([
                "id": id.uuidString, "createdAt": createdAt, "deck": "Тема",
                "question": "Демо \(index)\n**вопрос**", "answer": #"Литерал \n"# + "\n- Ответ"
            ])
        }
        data["cards"] = cards
        data["snapshot_version"] = 4
        data["lessons"] = [[
            "id": lessonID.uuidString, "title": "Введение", "course": "Демо",
            "source_url": "https://example.org/video", "createdAt": createdAt,
            "card_ids": ids.map(\.uuidString)
        ] as [String: Any]]
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1, "base_revision": revision, "data": data
        ])
        let (_, writeResponse) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((writeResponse as? HTTPURLResponse)?.statusCode, 200)
    }
}
