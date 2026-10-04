import Foundation

/// Which backend the app talks to. Mock runs a scripted p_012 day in process.
nonisolated enum AppMode: String, CaseIterable, Sendable {
    case mock, live
}

/// What chat needs from a backend (CONTRACT section 6, plus PATCH /meals for portion edits).
nonisolated protocol ChatService: Sendable {
    /// One chat turn as server-sent events. Cancel the consuming task to stop it.
    func chat(_ message: String, conversationId: String?) -> AsyncThrowingStream<ChatEvent, Error>
    /// PATCH /meals. On a participant's day the backend re-simulates and returns the new likely peak (1.6).
    func updateMeal(id: String, items: [MealItem]) async throws -> SavedMeal
}

/// Everything the app needs from a backend. The live and mock versions emit identical events,
/// so nothing downstream knows which one is running.
nonisolated protocol GummiService: ChatService {
    var mode: AppMode { get }
    func health() async throws -> Health
    func snapshot() async throws -> GummiState
    func feed() async throws -> [StoryCard]
    func fleet() async throws -> Fleet
    func follow(_ userId: String?) async throws -> GummiState
    func logDueMeal(dueId: String) async throws -> Meal
    func startStream() async throws -> StreamStatus
    func stopStream() async throws -> StreamStatus
    func pauseStream() async throws -> StreamStatus
    func resumeStream() async throws -> StreamStatus
    func setStreamSpeed(_ speed: Double) async throws -> StreamStatus
    /// POST /events: walk_started, or walk_completed with the phone's counts.
    func sendWalkEvent(_ body: WalkEventBody) async throws
    /// GET /walks/latest. Throws 404 not_found before the first walk.
    func latestWalk() async throws -> WalkSummary
    /// POST /vitals. The backend adds every sample, so never send a window twice.
    func uploadSteps(_ samples: [StepSample]) async throws -> Int
    /// Live events plus connection status. Cancel the consuming task to disconnect.
    func events() -> AsyncStream<ServiceEvent>
}

nonisolated final class LiveGummiService: GummiService {
    let mode = AppMode.live
    let api: APIClient
    private let live: LiveClient

    init(config: AppConfig, session: URLSession = .shared, tuning: LiveClient.Tuning = .init()) {
        api = APIClient(config: config, session: session)
        live = LiveClient(api: api, tuning: tuning)
    }

    func health() async throws -> Health { try await api.health() }
    func snapshot() async throws -> GummiState { try await api.state() }
    func feed() async throws -> [StoryCard] { try await api.feed() }
    func fleet() async throws -> Fleet { try await api.fleet() }
    func follow(_ userId: String?) async throws -> GummiState { try await api.follow(userId) }
    func logDueMeal(dueId: String) async throws -> Meal { try await api.logDueMeal(dueId: dueId) }
    func startStream() async throws -> StreamStatus { try await api.startStream() }
    func stopStream() async throws -> StreamStatus { try await api.stopStream() }
    func pauseStream() async throws -> StreamStatus { try await api.pauseStream() }
    func resumeStream() async throws -> StreamStatus { try await api.resumeStream() }
    func setStreamSpeed(_ speed: Double) async throws -> StreamStatus { try await api.setStreamSpeed(speed) }
    func events() -> AsyncStream<ServiceEvent> { live.events() }
    func chat(_ message: String, conversationId: String?) -> AsyncThrowingStream<ChatEvent, Error> {
        api.chat(message: message, conversationId: conversationId)
    }
    func updateMeal(id: String, items: [MealItem]) async throws -> SavedMeal { try await api.updateMeal(id: id, items: items) }
    func sendWalkEvent(_ body: WalkEventBody) async throws { try await api.sendWalkEvent(body) }
    func latestWalk() async throws -> WalkSummary { try await api.latestWalk() }
    func uploadSteps(_ samples: [StepSample]) async throws -> Int { try await api.uploadSteps(samples) }
}

nonisolated extension GummiService {
    func setPaused(_ paused: Bool) async throws {
        _ = try await paused ? pauseStream() : resumeStream()
    }
}
