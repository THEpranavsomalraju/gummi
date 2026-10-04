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

/// One event from POST /chat (CONTRACT section 6). Used by chat in Phase 2.
nonisolated enum ChatEvent: Sendable {
    nonisolated enum ToolStatus: String, ContractEnum {
        case start, end
        case unknown = "_unknown"
        static let unknownValue = ToolStatus.unknown
    }

    case token(String)
    /// Tool names stay free strings: Backend adds tools without breaking the phone.
    case tool(name: String, status: ToolStatus)
    case card(cardType: String, payload: Data)
    case mood(Mood)
    case done(conversationId: String, traceId: String?)
    case error(code: String, message: String)
    case unknown(name: String)
}
