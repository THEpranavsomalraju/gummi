import Foundation

/// MockAPI: runs MockSession on a replay clock and pushes the same events the backend would.
/// Default pace: 6 replay minutes per wall second, so one replay hour takes 10 seconds and 05:00 to 21:00 about 2.7 minutes.
nonisolated final class MockGummiService: GummiService {
    let mode = AppMode.mock
    private let engine: MockEngine

    init(day: MockDay, minutesPerSecond: Double = 6) {
        engine = MockEngine(session: MockSession(day: day), minutesPerSecond: minutesPerSecond)
    }

    func health() async throws -> Health { Health(status: "ok", mode: .mock, version: "mock-p012-day6") }
    func snapshot() async throws -> GummiState { await engine.snapshot() }
    func feed() async throws -> [StoryCard] { await engine.cards() }
    func follow(_ userId: String?) async throws -> GummiState {
        guard userId == nil || userId == MockSession.participant else {
            throw APIError.http(status: 404, code: "not_found", message: "Mock mode only replays \(MockSession.participant)")
        }
        return await engine.follow(userId)
    }
    func logDueMeal(dueId: String) async throws -> Meal { try await engine.logDue(dueId) }
    func startStream() async throws -> StreamStatus { await engine.restart() }
    func stopStream() async throws -> StreamStatus { await engine.setPaused(true) }
    func pauseStream() async throws -> StreamStatus { await engine.setPaused(true) }
    func resumeStream() async throws -> StreamStatus { await engine.setPaused(false) }
    /// `speed` is the contract's replay multiplier (60 means one replay minute per wall second).
    func setStreamSpeed(_ speed: Double) async throws -> StreamStatus { await engine.setSpeed(speed / 60) }

    func events() -> AsyncStream<ServiceEvent> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await engine.subscribe(id, continuation) }
            continuation.onTermination = { [engine] _ in Task { await engine.unsubscribe(id) } }
        }
    }
}

actor MockEngine {
    private var session: MockSession
    private var minutesPerSecond: Double
    private var paused = false
    private var resumeAt: Date?
    private var lastTick = Date.now
    private var lastStatePush = Date.distantPast
    private var subscribers: [UUID: AsyncStream<ServiceEvent>.Continuation] = [:]
    private var ticker: Task<Void, Never>?

    init(session: MockSession, minutesPerSecond: Double) {
        self.session = session
        self.minutesPerSecond = minutesPerSecond
    }

    func subscribe(_ id: UUID, _ continuation: AsyncStream<ServiceEvent>.Continuation) {
        subscribers[id] = continuation
        continuation.yield(.connection(.live))
        continuation.yield(.live(.state(snapshot())))
        if ticker == nil {
            lastTick = .now
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    await self?.tick()
                }
            }
        }
    }

    func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty {
            ticker?.cancel()
            ticker = nil
        }
    }

    func snapshot() -> GummiState {
        session.snapshot(wallNow: .now, paused: paused, minutesPerSecond: minutesPerSecond)
    }

    func cards() -> [StoryCard] { session.following == nil ? [] : session.cards }

    func follow(_ userId: String?) -> GummiState {
        session.following = userId
        pushState()
        return snapshot()
    }

    func logDue(_ dueId: String) throws -> Meal {
        let (meal, events) = try session.logDue(dueId: dueId)
        events.forEach { broadcast(.live($0)) }
        pushState()
        return meal
    }

    func restart() -> StreamStatus {
        session.reset()
        paused = false
        resumeAt = nil
        pushState()
        return snapshot().stream
    }

    func setPaused(_ value: Bool) -> StreamStatus {
        paused = value
        resumeAt = nil
        lastTick = .now
        pushState()
        return snapshot().stream
    }

    func setSpeed(_ value: Double) -> StreamStatus {
        minutesPerSecond = max(0.1, value)
        pushState()
        return snapshot().stream
    }

    private func tick() {
        let now = Date.now
        defer { lastTick = now }
        if let resumeAt, now >= resumeAt {
            paused = false
            self.resumeAt = nil
            pushState()
        }
        guard !paused else { return }
        if session.minute >= MockSession.endMinute {
            session.reset()
            pushState()
            return
        }
        let target = session.minute + now.timeIntervalSince(lastTick) * minutesPerSecond
        var changed = false
        for output in session.advance(to: target, wallNow: now) {
            switch output {
            case .event(let event):
                broadcast(.live(event))
                changed = true
            case .pause(let seconds):
                paused = true
                resumeAt = now.addingTimeInterval(seconds)
                changed = true
            }
        }
        // State at most once per second, or right after a scripted beat (CONTRACT section 5).
        if changed || now.timeIntervalSince(lastStatePush) >= 1 { pushState() }
    }

    private func pushState() {
        lastStatePush = .now
        broadcast(.live(.state(snapshot())))
    }

    private func broadcast(_ event: ServiceEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }
}
