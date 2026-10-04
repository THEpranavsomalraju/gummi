import HealthKit
import SwiftUI

/// Temporary Phase 0B screen: proves HealthKit step access and the backend token flow.
/// Deleted when the app shell lands.
struct SpikeView: View {
    @State private var stepsResult = "Not requested yet"
    @State private var backendResult = "Not pinged yet"
    @State private var isWorking = false

    private let healthStore = HKHealthStore()

    var body: some View {
        NavigationStack {
            List {
                Section("HealthKit") {
                    Button("Allow step access") { Task { await requestSteps() } }
                    Text(stepsResult).foregroundStyle(.secondary)
                }
                Section("Backend") {
                    Button("Ping backend") { Task { await pingBackend() } }
                    Text(backendResult).foregroundStyle(.secondary)
                }
            }
            .disabled(isWorking)
            .navigationTitle("Gummi spikes")
        }
    }

    private func requestSteps() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            stepsResult = "Health data is not available on this device."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let stepType = HKQuantityType(.stepCount)
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [stepType])
            let start = Calendar.current.startOfDay(for: .now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
            let descriptor = HKStatisticsQueryDescriptor(
                predicate: HKSamplePredicate.quantitySample(type: stepType, predicate: predicate),
                options: .cumulativeSum
            )
            let steps = try await descriptor.result(for: healthStore)?
                .sumQuantity()?.doubleValue(for: .count()) ?? 0
            stepsResult = "Steps today: \(Int(steps))"
        } catch {
            stepsResult = "HealthKit error: \(error.localizedDescription)"
        }
    }

    private func pingBackend() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let config = try AppConfig.load()
            let tokens = TokenProvider(config: config)
            let started = Date.now
            var request = URLRequest(url: config.apiBaseURL.appending(path: "health"))
            request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "Authorization")
            request.setValue(config.userID, forHTTPHeaderField: "X-User-Id")
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            let ms = Int(Date.now.timeIntervalSince(started) * 1000)
            let mode = http?.value(forHTTPHeaderField: "X-Gummi-Mode") ?? "none"
            let body = String(decoding: data, as: UTF8.self)
            backendResult = "HTTP \(http?.statusCode ?? 0) in \(ms) ms, mode \(mode)\n\(body)"
        } catch {
            backendResult = "\(error)"
        }
    }
}

#Preview {
    SpikeView()
}
