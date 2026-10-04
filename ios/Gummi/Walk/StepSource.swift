import CoreMotion
import Foundation

/// Live steps for a walk: cumulative steps since start and the current pace in steps per minute.
nonisolated struct StepReading: Equatable, Sendable {
    var steps: Int
    var cadenceSpm: Int?
}

nonisolated protocol StepSource: Sendable {
    /// Readings from `start` until the consuming task is cancelled.
    func readings(from start: Date) -> AsyncStream<StepReading>
}

/// The iPhone's pedometer (Core Motion). Cadence comes from `currentCadence` (steps per second).
nonisolated final class PedometerStepSource: StepSource {
    static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    func readings(from start: Date) -> AsyncStream<StepReading> {
        AsyncStream { continuation in
            let box = PedometerBox()
            box.pedometer.startUpdates(from: start) { data, _ in
                guard let data else { return }
                continuation.yield(StepReading(steps: data.numberOfSteps.intValue,
                                               cadenceSpm: data.currentCadence.map { Int(($0.doubleValue * 60).rounded()) }))
            }
            continuation.onTermination = { _ in box.pedometer.stopUpdates() }
        }
    }

    /// CMPedometer is thread-safe for start and stop but isn't marked Sendable.
    private final class PedometerBox: @unchecked Sendable {
        let pedometer = CMPedometer()
    }
}

/// A steady walker at about 110 steps per minute, for the Simulator and screenshots (`-gummi.fakeSteps`).
nonisolated final class SimulatedStepSource: StepSource {
    func readings(from start: Date) -> AsyncStream<StepReading> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let seconds = Date.now.timeIntervalSince(start)
                    continuation.yield(StepReading(steps: Int(seconds * 110 / 60), cadenceSpm: 108 + Int(seconds) % 5))
                    try? await Task.sleep(for: .seconds(1))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

nonisolated enum StepSources {
    /// The pedometer when it works, otherwise the simulated walker.
    static func standard(defaults: UserDefaults = .standard) -> any StepSource {
        if defaults.bool(forKey: "gummi.fakeSteps") || !PedometerStepSource.isAvailable { return SimulatedStepSource() }
        return PedometerStepSource()
    }
}
