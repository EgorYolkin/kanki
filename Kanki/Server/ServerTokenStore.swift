import Foundation
import Security

enum ServerTokenStoreError: LocalizedError {
    case keychain(OSStatus)
    case file(Error)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            "Ошибка Keychain: \(status)"
        case .file(let error):
            "Ошибка файла токена: \(error.localizedDescription)"
        }
    }
}

/// Токен сервера: Keychain на подписанной сборке, файл в sandbox — если
/// симулятор без подписи не имеет Keychain-entitlement (`errSecMissingEntitlement`).
enum ServerTokenStore {
    private static let service = "app.kanki.server"
    private static let account = "token"
    private static let fileName = "server-token"

    private static var tokenFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Kanki", directoryHint: .isDirectory)
            .appending(path: fileName)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load() throws -> String? {
        do {
            if let token = try keychainLoad() {
                return token
            }
            return try fileLoad()
        } catch let error as ServerTokenStoreError {
            if case .keychain(let status) = error, status == errSecMissingEntitlement {
                return try fileLoad()
            }
            throw error
        }
    }

    static func save(_ token: String) throws {
        do {
            try keychainSave(token)
        } catch let error as ServerTokenStoreError {
            if case .keychain(let status) = error, status == errSecMissingEntitlement {
                try fileSave(token)
                return
            }
            throw error
        }
    }

    static func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound, status != errSecMissingEntitlement {
            throw ServerTokenStoreError.keychain(status)
        }
        try fileDelete()
    }

    private static func keychainLoad() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw ServerTokenStoreError.keychain(status)
        }
    }

    private static func keychainSave(_ token: String) throws {
        let data = Data(token.utf8)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw ServerTokenStoreError.keychain(addStatus)
            }
        default:
            throw ServerTokenStoreError.keychain(status)
        }
    }

    private static func fileLoad() throws -> String? {
        guard FileManager.default.fileExists(atPath: tokenFileURL.path) else {
            return nil
        }
        do {
            return try String(contentsOf: tokenFileURL, encoding: .utf8)
        } catch {
            throw ServerTokenStoreError.file(error)
        }
    }

    private static func fileSave(_ token: String) throws {
        do {
            try FileManager.default.createDirectory(
                at: tokenFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            #if os(iOS)
            try Data(token.utf8).write(to: tokenFileURL, options: [.atomic, .completeFileProtection])
            #else
            try Data(token.utf8).write(to: tokenFileURL, options: .atomic)
            #endif
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: tokenFileURL.path
            )
        } catch {
            throw ServerTokenStoreError.file(error)
        }
    }

    private static func fileDelete() throws {
        guard FileManager.default.fileExists(atPath: tokenFileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: tokenFileURL)
        } catch {
            throw ServerTokenStoreError.file(error)
        }
    }
}
