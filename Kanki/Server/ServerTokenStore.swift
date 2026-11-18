import Foundation
import Security

enum ServerTokenStoreError: LocalizedError {
    case keychain(OSStatus)
    case file(Error)
    case invalidOrigin

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Ошибка Keychain: \(status)"
        case .file(let error):
            "Ошибка файла токена: \(error.localizedDescription)"
        case .invalidOrigin:
            "Не удалось определить адрес сервера"
        }
    }
}

/// Хранит отдельные учётные данные для снимка и дельты, привязанные к origin.
/// Keychain недоступен без entitlement: в этой сборке данные хранятся в sandbox.
enum ServerTokenStore {
    enum Scope: String, CaseIterable {
        case snapshot
        case delta
    }

    struct Credentials: Codable, Equatable {
        let token: String
        let pin: String

        init(token: String, pin: String = "") {
            self.token = token
            self.pin = pin
        }
    }

    private struct Origin: Codable, Equatable {
        let scheme: String
        let host: String
        let port: Int

        init?(_ configuration: ServerConfiguration) {
            let url = configuration.baseURL
            guard let scheme = url.scheme?.lowercased(),
                  let host = url.host(percentEncoded: false)?.lowercased() else { return nil }
            self.scheme = scheme
            self.host = host
            self.port = url.port ?? (scheme == "https" ? 443 : 80)
        }
    }

    private struct Record: Codable {
        let origin: Origin
        let credentials: Credentials
    }

    private static let service = "app.kanki.server"

    static func sameOrigin(_ first: ServerConfiguration, _ second: ServerConfiguration) -> Bool {
        guard let origin = Origin(first) else { return false }
        return Origin(second) == origin
    }

    static func load(for scope: Scope, configuration: ServerConfiguration) throws -> Credentials? {
        guard let origin = Origin(configuration) else { throw ServerTokenStoreError.invalidOrigin }
        let data: Data?
        do {
            data = try keychainData(account: scope.rawValue) ?? fileLoad(account: scope.rawValue)
        } catch ServerTokenStoreError.keychain(let status) where status == errSecMissingEntitlement {
            data = try fileLoad(account: scope.rawValue)
        }
        guard let data else { return nil }
        let record = try JSONDecoder().decode(Record.self, from: data)
        return record.origin == origin ? record.credentials : nil
    }

    static func save(_ credentials: Credentials, for scope: Scope, configuration: ServerConfiguration) throws {
        guard let origin = Origin(configuration) else { throw ServerTokenStoreError.invalidOrigin }
        let data = try JSONEncoder().encode(Record(origin: origin, credentials: credentials))
        let account = scope.rawValue
        do {
            try keychainSave(data, account: account)
        } catch ServerTokenStoreError.keychain(let status) where status == errSecMissingEntitlement {
            try fileSave(data, account: account)
            return
        }
        // Успешная запись в Keychain не должна оставлять устаревшую копию.
        try? fileDelete(account: account)
    }

    static func deleteAll() throws {
        for scope in Scope.allCases {
            try delete(account: scope.rawValue)
        }
        // Старый токен не имел привязки к origin. Его никогда не читаем.
        try delete(account: "token")
    }

    static func tokenFileURL(for scope: Scope) -> URL {
        tokenFileURL(account: scope.rawValue)
    }

    static func hasKeychainCredentials(for scope: Scope) throws -> Bool {
        try keychainData(account: scope.rawValue) != nil
    }

    private static func tokenFileURL(account: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Kanki", directoryHint: .isDirectory)
            .appending(path: "server-\(account)")
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound, status != errSecMissingEntitlement {
            throw ServerTokenStoreError.keychain(status)
        }
        try fileDelete(account: account)
    }

    private static func keychainData(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw ServerTokenStoreError.keychain(status)
        }
    }

    private static func keychainSave(_ data: Data, account: String) throws {
        let update = [kSecValueData as String: data]
        let query = baseQuery(account: account)
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addition = query
            addition[kSecValueData as String] = data
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ServerTokenStoreError.keychain(addStatus)
            }
        default:
            throw ServerTokenStoreError.keychain(status)
        }
    }

    private static func fileLoad(account: String) throws -> Data? {
        let tokenFileURL = tokenFileURL(account: account)
        guard FileManager.default.fileExists(atPath: tokenFileURL.path) else {
            return nil
        }
        do {
            return try Data(contentsOf: tokenFileURL)
        } catch {
            throw ServerTokenStoreError.file(error)
        }
    }

    private static func fileSave(_ data: Data, account: String) throws {
        let tokenFileURL = tokenFileURL(account: account)
        do {
            try FileManager.default.createDirectory(
                at: tokenFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            #if os(iOS)
            try data.write(to: tokenFileURL, options: [.atomic, .completeFileProtection])
            #else
            try data.write(to: tokenFileURL, options: .atomic)
            #endif
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tokenFileURL.path
            )
        } catch {
            throw ServerTokenStoreError.file(error)
        }
    }

    private static func fileDelete(account: String) throws {
        let tokenFileURL = tokenFileURL(account: account)
        guard FileManager.default.fileExists(atPath: tokenFileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: tokenFileURL)
        } catch {
            throw ServerTokenStoreError.file(error)
        }
    }
}

struct ServerCredentialDraft {
    private enum InputError: LocalizedError {
        case invalidURL
        case invalidDeltaURL
        case missingToken

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                "Укажите адрес вида http://100.x.y.z:8000"
            case .invalidDeltaURL:
                "Укажите HTTPS-адрес для обмена изменениями"
            case .missingToken:
                "Укажите токен сервера"
            }
        }
    }

    var address = ""
    var token = ""
    var pin = ""

    mutating func update(_ field: WritableKeyPath<Self, String>, to value: String) -> Bool {
        guard self[keyPath: field] != value else { return false }
        if field == \.address {
            token = ""
            pin = ""
        }
        self[keyPath: field] = value
        return true
    }

    func connection(for scope: ServerTokenStore.Scope) throws -> (ServerConfiguration, ServerTokenStore.Credentials) {
        guard let configuration = ServerConfiguration(rawValue: address) else {
            throw scope == .delta ? InputError.invalidDeltaURL : InputError.invalidURL
        }
        if scope == .delta, configuration.baseURL.scheme?.lowercased() != "https" {
            throw InputError.invalidDeltaURL
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw InputError.missingToken }
        let pin = scope == .delta ? pin.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (configuration, .init(token: token, pin: pin))
    }
}
