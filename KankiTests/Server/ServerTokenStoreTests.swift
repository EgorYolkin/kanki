import Security
import XCTest

@testable import Kanki

final class ServerTokenStoreTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try ServerTokenStore.deleteAll()
    }

    override func tearDown() {
        try? ServerTokenStore.deleteAll()
        super.tearDown()
    }

    /// Токен живёт ровно в одном источнике: успешная запись в Keychain не
    /// оставляет файловый fallback, иначе неподписанный запуск прочитает
    /// устаревший токен. В неподписанном симуляторе легитимен файл.
    func testSaveKeepsSingleSourceOfTruth() throws {
        let configuration = try server("https://delta.example")
        let credentials = ServerTokenStore.Credentials(token: "synthetic-token", pin: "synthetic-pin")
        try ServerTokenStore.save(credentials, for: .delta, configuration: configuration)

        let storedInKeychain: Bool
        do {
            storedInKeychain = try ServerTokenStore.hasKeychainCredentials(for: .delta)
        } catch ServerTokenStoreError.keychain(let status) where status == errSecMissingEntitlement {
            // Неподписанный симулятор: Keychain недоступен, токен — в файле.
            storedInKeychain = false
        }
        let fallbackExists = FileManager.default.fileExists(
            atPath: ServerTokenStore.tokenFileURL(for: .delta).path
        )
        XCTAssertFalse(
            storedInKeychain && fallbackExists,
            "Успешная запись в Keychain должна удалять файловый fallback"
        )
        XCTAssertEqual(try ServerTokenStore.load(for: .delta, configuration: configuration), credentials)
    }

    func testCredentialsAreIsolatedByChannelAndOrigin() throws {
        let origin = try server("https://example.test")
        let sameOrigin = try server("https://EXAMPLE.test:443/")
        let otherHost = try server("https://other.example.test")
        let otherPort = try server("https://example.test:444")
        let cleartext = try server("http://example.test")
        let snapshot = ServerTokenStore.Credentials(token: "snapshot-only")
        let delta = ServerTokenStore.Credentials(token: "delta-only", pin: "delta-pin")

        try ServerTokenStore.save(delta, for: .delta, configuration: origin)
        XCTAssertNil(try ServerTokenStore.load(for: .snapshot, configuration: sameOrigin))
        XCTAssertEqual(try ServerTokenStore.load(for: .delta, configuration: sameOrigin), delta)
        XCTAssertNil(try ServerTokenStore.load(for: .delta, configuration: otherHost))
        XCTAssertNil(try ServerTokenStore.load(for: .delta, configuration: otherPort))
        XCTAssertNil(try ServerTokenStore.load(for: .delta, configuration: cleartext))

        try ServerTokenStore.save(snapshot, for: .snapshot, configuration: cleartext)
        XCTAssertEqual(try ServerTokenStore.load(for: .snapshot, configuration: cleartext), snapshot)
        XCTAssertNil(try ServerTokenStore.load(for: .snapshot, configuration: origin))
        XCTAssertEqual(try ServerTokenStore.load(for: .delta, configuration: origin), delta)
    }

    func testLegacyTokenIsNotLoadedByEitherChannel() throws {
        let directory = ServerTokenStore.tokenFileURL(for: .snapshot).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("unscoped-legacy-token".utf8).write(to: directory.appending(path: "server-token"))

        let configuration = try server("https://example.test")
        XCTAssertNil(try ServerTokenStore.load(for: .snapshot, configuration: configuration))
        XCTAssertNil(try ServerTokenStore.load(for: .delta, configuration: configuration))
    }

    func testEditingAddressDropsDraftTokenAndPinEvenIfAddressIsRestored() throws {
        let address = "https://example.test"
        var draft = ServerCredentialDraft(address: address, token: "delta-only", pin: "delta-pin")
        XCTAssertFalse(draft.update(\.address, to: address))
        XCTAssertTrue(draft.update(\.address, to: "https://other.example.test"))
        XCTAssertTrue(draft.update(\.address, to: address))
        XCTAssertThrowsError(try draft.connection(for: .delta))

        XCTAssertTrue(draft.update(\.token, to: " replacement-token "))
        let (_, credentials) = try draft.connection(for: .delta)
        XCTAssertEqual(credentials.token, "replacement-token")
        XCTAssertTrue(credentials.pin.isEmpty)
    }

    func testUnpinnedSnapshotAcceptsHTTPLocalAddressButDeltaRequiresTLS() throws {
        let draft = ServerCredentialDraft(address: "http://127.0.0.1:9", token: "snapshot", pin: "unused")
        let (_, credentials) = try draft.connection(for: .snapshot)
        XCTAssertTrue(credentials.pin.isEmpty)
        XCTAssertThrowsError(try draft.connection(for: .delta))
    }

    private func server(_ address: String) throws -> ServerConfiguration {
        try XCTUnwrap(ServerConfiguration(rawValue: address))
    }
}
