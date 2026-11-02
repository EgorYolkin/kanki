import Foundation

/// Проверенный адрес сервера Kanki. Поддерживает HTTP внутри Tailscale/LAN
/// и HTTPS для внешнего адреса; логин и пароль в URL не допускаются.
struct ServerConfiguration: Equatable {
    let baseURL: URL

    init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let components = URLComponents(string: trimmed),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil,
            components.path.isEmpty || components.path == "/"
        else {
            return nil
        }
        var normalized = components
        normalized.path = ""
        guard let url = normalized.url else { return nil }
        baseURL = url
    }

    var displayValue: String {
        baseURL.absoluteString
    }
}
