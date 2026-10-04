import Foundation

/// Fetches and caches the gummi-iphone OAuth token (client credentials, D-06).
/// Refreshes 5 minutes before expiry; call `invalidate()` after a 401 and retry once.
actor TokenProvider {
    struct TokenError: Error, CustomStringConvertible {
        let description: String
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
    }

    private let config: AppConfig
    private let session: URLSession
    private var token: String?
    private var expiresAt: Date = .distantPast
    private var inFlight: Task<String, Error>?

    init(config: AppConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func accessToken() async throws -> String {
        if let token, Date.now < expiresAt.addingTimeInterval(-300) { return token }
        if let inFlight { return try await inFlight.value }
        let task = Task { try await fetch() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }

    func invalidate() {
        token = nil
        expiresAt = .distantPast
    }

    private func fetch() async throws -> String {
        var request = URLRequest(url: config.tokenURL)
        request.httpMethod = "POST"
        let basic = Data("\(config.clientID):\(config.clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=client_credentials&scope=all-apis".utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw TokenError(description: "Token request failed with HTTP \(status)") }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        token = decoded.access_token
        expiresAt = Date.now.addingTimeInterval(decoded.expires_in)
        return decoded.access_token
    }
}
