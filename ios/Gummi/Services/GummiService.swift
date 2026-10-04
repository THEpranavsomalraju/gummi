import Foundation

/// Which backend the app talks to. Mock runs a scripted p_012 day in process.
nonisolated enum AppMode: String, CaseIterable, Sendable {
    case mock, live
}

/// Everything the app needs from a backend. The live and mock versions emit identical events,
/// so nothing downstream knows which one is running.
nonisolated protocol GummiService: Sendable {
    var mode: AppMode { get }
    func health() async throws -> Health
    func snapshot() async throws -> GummiState
    func feed() async throws -> [StoryCard]
    func follow(_ userId: String?) async throws -> GummiState
    func logDueMeal(dueId: String) async throws -> Meal
    func startStream() async throws -> StreamStatus
    func stopStream() async throws -> StreamStatus
    func pauseStream() async throws -> StreamStatus
    func resumeStream() async throws -> StreamStatus
    func setStreamSpeed(_ speed: Double) async throws -> StreamStatus
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
    func follow(_ userId: String?) async throws -> GummiState { try await api.follow(userId) }
    func logDueMeal(dueId: String) async throws -> Meal { try await api.logDueMeal(dueId: dueId) }
    func startStream() async throws -> StreamStatus { try await api.startStream() }
    func stopStream() async throws -> StreamStatus { try await api.stopStream() }
    func pauseStream() async throws -> StreamStatus { try await api.pauseStream() }
    func resumeStream() async throws -> StreamStatus { try await api.resumeStream() }
    func setStreamSpeed(_ speed: Double) async throws -> StreamStatus { try await api.setStreamSpeed(speed) }
    func events() -> AsyncStream<ServiceEvent> { live.events() }
}
