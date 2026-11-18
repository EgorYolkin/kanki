import XCTest

@testable import Kanki

final class ServerTokenStoreTests: XCTestCase {
    override func tearDown() {
        try? ServerTokenStore.delete()
        super.tearDown()
    }

    /// Токен живёт ровно в одном источнике: успешная запись в Keychain не
    /// оставляет файловый fallback, иначе неподписанный запуск прочитает
    /// устаревший токен. В неподписанном симуляторе легитимен файл.
    @MainActor
    func testSaveKeepsSingleSourceOfTruth() throws {
        let token = "token-\(UUID().uuidString)"

        let origin = try XCTUnwrap(ServerConfiguration(rawValue: "https://study.example"))
        try ServerTokenStore.commit(token, for: origin)

        let storedInKeychain: Bool
        do {
            storedInKeychain = try ServerTokenStore.keychainToken() != nil
        } catch ServerTokenStoreError.keychain(let status) where status == errSecMissingEntitlement {
            // Неподписанный симулятор: Keychain недоступен, токен — в файле.
            storedInKeychain = false
        }
        let fallbackExists = FileManager.default.fileExists(
            atPath: ServerTokenStore.tokenFileURL.path
        )
        XCTAssertFalse(
            storedInKeychain && fallbackExists,
            "Успешная запись в Keychain должна удалять файловый fallback"
        )
        XCTAssertEqual(try ServerTokenStore.load(for: origin), token)
    }

    @MainActor
    func testNewOriginCannotReadOldOrPartiallyCommittedCredential() throws {
        let first = try XCTUnwrap(ServerConfiguration(rawValue: "https://first.example"))
        let second = try XCTUnwrap(ServerConfiguration(rawValue: "https://second.example"))
        try ServerTokenStore.commit("first-token", for: first)
        XCTAssertNil(try ServerTokenStore.load(for: second))
        UserDefaults.standard.set(second.displayValue, forKey: "serverURL")
        XCTAssertNil(try ServerTokenStore.load(for: second))
        try ServerTokenStore.commit("second-token", for: second)
        XCTAssertNil(try ServerTokenStore.load(for: first))
        XCTAssertEqual(try ServerTokenStore.load(for: second), "second-token")
    }

    func testLegacyTokenStillWorksOnlyForSavedDestination() throws {
        try ServerTokenStore.delete()
        let file = ServerTokenStore.tokenFileURL
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: file)
        UserDefaults.standard.set("HTTPS://STUDY.EXAMPLE:443/", forKey: "serverURL")
        let destination = try XCTUnwrap(ServerConfiguration(rawValue: "https://study.example"))
        let other = try XCTUnwrap(ServerConfiguration(rawValue: "http://study.example"))
        XCTAssertEqual(try ServerTokenStore.load(for: destination), "legacy")
        XCTAssertNil(try ServerTokenStore.load(for: other))
    }
}
