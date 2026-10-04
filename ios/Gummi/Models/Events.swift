import Foundation

/// One event from GET /live (CONTRACT section 5).
nonisolated enum LiveEvent: Sendable, Hashable {
    case state(GummiState)
    case card(StoryCard)
    case grade(Grade)
    case alert(GummiAlert)
    case mood(Mood)
    case ping(Date?)
    /// An event name this build doesn't know. Ignored, never fatal.
    case unknown(name: String)

    nonisolated private struct MoodPayload: Decodable { let mood: Mood }
    nonisolated private struct PingPayload: Decodable { let t: Date? }

    /// Decodes one server-sent event. Throws only when a known event carries malformed JSON.
    static func decode(event: String, data: Data, using decoder: JSONDecoder = JSONCoding.decoder()) throws -> LiveEvent {
        switch event {
        case "state": .state(try decoder.decode(GummiState.self, from: data))
        case "card": .card(try decoder.decode(StoryCard.self, from: data))
        case "grade": .grade(try decoder.decode(Grade.self, from: data))
        case "alert": .alert(try decoder.decode(GummiAlert.self, from: data))
        case "mood": .mood(try decoder.decode(MoodPayload.self, from: data).mood)
        case "ping": .ping(try? decoder.decode(PingPayload.self, from: data).t)
        default: .unknown(name: event)
        }
    }
}

/// One event from POST /chat (CONTRACT section 6).
nonisolated enum ChatEvent: Sendable, Hashable {
    nonisolated enum ToolStatus: String, ContractEnum {
        case start, end
        case unknown = "_unknown"
        static let unknownValue = ToolStatus.unknown
    }

    case token(String)
    /// Tool names stay free strings: Backend adds tools without breaking the phone.
    case tool(name: String, status: ToolStatus)
    case card(ChatCard)
    case mood(Mood)
    case done(conversationId: String, traceId: String?)
    case error(code: String, message: String)
    /// An event name or card type this build doesn't know. Ignored, never fatal.
    case unknown(name: String)

    nonisolated private struct TokenPayload: Decodable { let text: String }
    nonisolated private struct ToolPayload: Decodable { let name: String; let status: ToolStatus }
    nonisolated private struct MoodPayload: Decodable { let mood: Mood }
    nonisolated private struct DonePayload: Decodable { let conversationId: String; let traceId: String? }
    nonisolated private struct ErrorPayload: Decodable { let code: String; let message: String }

    /// Decodes one server-sent event. Throws only when a known event carries malformed JSON.
    static func decode(event: String, data: Data, using decoder: JSONDecoder = JSONCoding.decoder()) throws -> ChatEvent {
        switch event {
        case "token":
            return .token(try decoder.decode(TokenPayload.self, from: data).text)
        case "tool":
            let tool = try decoder.decode(ToolPayload.self, from: data)
            return .tool(name: tool.name, status: tool.status)
        case "card":
            return try ChatCard.decode(data, using: decoder).map(ChatEvent.card) ?? .unknown(name: "card")
        case "mood":
            return .mood(try decoder.decode(MoodPayload.self, from: data).mood)
        case "done":
            let done = try decoder.decode(DonePayload.self, from: data)
            return .done(conversationId: done.conversationId, traceId: done.traceId)
        case "error":
            let error = try decoder.decode(ErrorPayload.self, from: data)
            return .error(code: error.code, message: error.message)
        default:
            return .unknown(name: event)
        }
    }
}
