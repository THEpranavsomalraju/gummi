import Foundation

/// Typed errors for the contract's error shape `{"error": {"code", "message"}}` (CONTRACT section 1, codes in 1.3).
nonisolated enum APIError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Secrets.xcconfig.local is missing values.
    case notConfigured(String)
    /// 401 even after one fresh token. The proxy's own 401 has an empty body.
    case unauthorized
    /// Any other non-2xx with the contract's code and message when the body has them.
    case http(status: Int, code: String, message: String)
    case transport(String)
    case decoding(String)

    /// The contract error code, when there is one (for example "due_already_logged" or "warming_up").
    var code: String? {
        switch self {
        case .http(_, let code, _): code
        case .unauthorized: "unauthorized"
        default: nil
        }
    }

    var description: String {
        switch self {
        case .notConfigured(let detail): detail
        case .unauthorized: "Not authorized. Check the gummi-iphone client secret."
        case .http(let status, let code, let message): "HTTP \(status) \(code): \(message)"
        case .transport(let detail): "Network: \(detail)"
        case .decoding(let detail): "Unexpected response: \(detail)"
        }
    }

    static func from(status: Int, body: Data) -> APIError {
        if status == 401 { return .unauthorized }
        if let parsed = try? JSONCoding.decoder().decode(APIErrorBody.self, from: body) {
            return .http(status: status, code: parsed.error.code, message: parsed.error.message)
        }
        let text = String(decoding: body.prefix(200), as: UTF8.self)
        // Databricks answers for a stopped App with its own HTML page; never show HTML to a person.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            if status == 503 { return .http(status: 503, code: "app_unavailable", message: "Gummi's server is asleep") }
            return .http(status: status, code: "http_\(status)", message: HTTPURLResponse.localizedString(forStatusCode: status))
        }
        return .http(status: status, code: "http_\(status)",
                     message: text.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : text)
    }

    static func decoding(_ error: Error) -> APIError {
        guard let error = error as? DecodingError else { return .decoding(String(describing: error)) }
        switch error {
        case .keyNotFound(let key, let context):
            return .decoding("missing \(path(context.codingPath + [key]))")
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return .decoding("\(path(context.codingPath)): \(context.debugDescription)")
        @unknown default:
            return .decoding(String(describing: error))
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
    }
}
