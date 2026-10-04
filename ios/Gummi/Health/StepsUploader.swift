import Foundation
import HealthKit

/// HealthKit steps to POST /vitals in 5-minute buckets. The backend adds every sample it gets, so a cursor
/// (the end of the last uploaded bucket) makes sure no window is ever sent twice.
final class StepsUploader {
    nonisolated static let bucket: TimeInterval = 5 * 60
    nonisolated static let lookback: TimeInterval = 2 * 3600
    nonisolated static let cursorKey = "gummi.stepsCursor"

    private let store = HKHealthStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The completed 5-minute buckets to upload: from the cursor (at most 2 hours back) to the last full bucket.
    /// Nil when nothing new has completed yet.
    nonisolated static func window(cursor: Date?, now: Date) -> DateInterval? {
        let lastFull = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / bucket).rounded(.down) * bucket)
        let earliest = Date(timeIntervalSince1970: ((now.timeIntervalSince1970 - lookback) / bucket).rounded(.down) * bucket)
        let start = max(cursor ?? earliest, earliest)
        return start < lastFull ? DateInterval(start: start, end: lastFull) : nil
    }

    /// Reads and uploads new buckets. Returns the steps sent. Errors leave the cursor alone, so the next run retries.
    func uploadNew(using service: any GummiService, now: Date = .now) async throws -> Int {
        guard HKHealthStore.isHealthDataAvailable(), !defaults.bool(forKey: "gummi.noPrompts"),
              let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        try await store.requestAuthorization(toShare: [], read: [type])
        let cursor = defaults.object(forKey: Self.cursorKey) as? Date
        guard let window = Self.window(cursor: cursor, now: now) else { return 0 }
        let samples = try await buckets(type, in: window)
        if !samples.isEmpty { _ = try await service.uploadSteps(samples) }
        defaults.set(window.end, forKey: Self.cursorKey)
        return samples.map(\.value).reduce(0, +)
    }

    private func buckets(_ type: HKQuantityType, in window: DateInterval) async throws -> [StepSample] {
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictStartDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum, anchorDate: window.start, intervalComponents: DateComponents(minute: 5))
        let collection = try await descriptor.result(for: store)
        var samples: [StepSample] = []
        collection.enumerateStatistics(from: window.start, to: window.end) { statistics, _ in
            let steps = Int(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            if steps > 0 { samples.append(StepSample(value: steps, start: statistics.startDate, end: statistics.endDate)) }
        }
        return samples
    }
}
