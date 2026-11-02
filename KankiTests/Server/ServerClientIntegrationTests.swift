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
    }
}
