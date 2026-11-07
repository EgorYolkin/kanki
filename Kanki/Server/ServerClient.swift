import Foundation

/// HTTP-клиент сервера Kanki. Токен передаётся только в заголовке и не логируется.
actor ServerClient {
    private let baseURL: URL
    private let token: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        configuration: ServerConfiguration,
        token: String,
        session: URLSession = .shared
    ) {
        self.baseURL = configuration.baseURL
        self.token = token
        self.session = session
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func identity() async throws -> ServerIdentity {
        try await request(path: "v1/me", method: "GET")
    }

    /// Снимок, приведённый к проводному формату: `iso8601` теряет дробные
    /// секунды, поэтому локальный снимок сравнивается с серверным после такого
    /// же round-trip. Иначе применённый, но не подтверждённый PUT выглядит
    /// конфликтом вместо `.adoptRevision`.
    static func wireNormalized(_ snapshot: LearningSnapshot) -> LearningSnapshot? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return nil }
        return try? decoder.decode(LearningSnapshot.self, from: data)
    }

    func fetchSnapshot() async throws -> ServerSnapshot {
        try await request(path: "v1/snapshot", method: "GET")
    }

    func push(
        snapshot: LearningSnapshot,
        baseRevision: Int
    ) async throws -> ServerSnapshot {
        let body = try encoder.encode(
            ServerSnapshotWrite(snapshot: snapshot, baseRevision: baseRevision)
        )
        return try await request(path: "v1/snapshot", method: "PUT", body: body)
    }

    private func request<T: Decodable>(
        path: String,
        method: String,
        body: Data? = nil
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ServerError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw ServerError.decoding
            }
        case 401:
            throw ServerError.unauthorized
        case 409:
            throw ServerError.conflict(currentRevision: conflictRevision(from: data))
        default:
            throw ServerError.http(status: http.statusCode)
        }
    }

    private func conflictRevision(from data: Data) -> Int {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = object["detail"] as? [String: Any],
            let revision = detail["current_revision"] as? Int
        else {
            return 0
        }
        return revision
    }
}
