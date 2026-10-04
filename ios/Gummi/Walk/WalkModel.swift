import Foundation
import Observation

/// What opens the walk screen, with the suggested minutes.
nonisolated struct WalkRequest: Identifiable, Equatable, Sendable {
    let id = UUID()
    var minutes: Int = 10
}

/// One walk: walk_started, live steps and cadence, then walk_completed and the summary from GET /walks/latest.
@Observable
final class WalkModel {
    enum Phase: Equatable {
        case walking
        case finishing
        case done(WalkSummary?)
        /// Shorter than a minute: nothing was sent, nothing is shown.
        case discarded
        case failed(String)
    }

    nonisolated static let minimumSeconds: TimeInterval = 60

    let targetMinutes: Int
    private(set) var phase = Phase.walking
    private(set) var startedAt: Date
    private(set) var steps = 0
    private(set) var cadenceSpm: Int?

    @ObservationIgnored private let service: (any GummiService)?
    @ObservationIgnored private let source: any StepSource
    @ObservationIgnored private var readingTask: Task<Void, Never>?
    @ObservationIgnored private let clock: () -> Date

    init(minutes: Int, service: (any GummiService)?, source: any StepSource, clock: @escaping () -> Date = { .now }) {
        targetMinutes = max(1, minutes)
        self.service = service
        self.source = source
        self.clock = clock
        startedAt = clock()
    }

    /// Sends walk_started and starts counting.
    func start() {
        startedAt = clock()
        let start = startedAt
        Task { [service] in try? await service?.sendWalkEvent(.started(at: start)) }
        readingTask = Task { [weak self, source] in
            for await reading in source.readings(from: start) {
                guard let self else { return }
                self.steps = max(self.steps, reading.steps)
                self.cadenceSpm = reading.cadenceSpm
            }
        }
    }

    /// Average pace over the whole walk.
    static func averageCadence(steps: Int, seconds: TimeInterval) -> Int {
        seconds > 0 ? Int((Double(steps) / (seconds / 60)).rounded()) : 0
    }

    /// Ends the walk. Under a minute it's discarded; otherwise walk_completed, then the summary.
    func end() async {
        guard phase == .walking else { return }
        readingTask?.cancel()
        readingTask = nil
        let endedAt = clock()
        let seconds = endedAt.timeIntervalSince(startedAt)
        guard seconds >= Self.minimumSeconds else {
            phase = .discarded
            return
        }
        guard let service else {
            phase = .failed("Not connected")
            return
        }
        phase = .finishing
        do {
            try await service.sendWalkEvent(.completed(at: endedAt, startedAt: startedAt, steps: steps,
                                                       cadenceSpm: Self.averageCadence(steps: steps, seconds: seconds)))
            phase = .done(try? await service.latestWalk())
        } catch {
            phase = .failed("\(error)")
        }
    }

    func cancel() {
        readingTask?.cancel()
        readingTask = nil
    }
}
