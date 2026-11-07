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
    func testSaveKeepsSingleSourceOfTruth() throws {
        let token = "token-\(UUID().uuidString)"

        try ServerTokenStore.save(token)

        let storedInKeychain: Bool
        do {
            storedInKeychain = try ServerTokenStore.keychainToken() == token
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
        XCTAssertEqual(try ServerTokenStore.load(), token)
    }
}
