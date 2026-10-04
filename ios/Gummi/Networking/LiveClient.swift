import Foundation

/// Health of the live channel, shown by the app so updates never silently stop.
nonisolated enum ConnectionStatus: Equatable, Sendable {
    case idle
    case connecting
    case live
    case reconnecting(attempt: Int)
    /// /live is down; /state is polled every 15 seconds meanwhile.
    case polling
    case offline(String)
}

nonisolated enum ServiceEvent: Sendable {
    case live(LiveEvent)
    case connection(ConnectionStatus)
}

/// GET /live over URLSession bytes, parsed by SSEParser (CONTRACT section 5).
/// Reconnects with backoff, refreshes the token on 401, polls /state while down.
/// The URLRequest timeout is the no-bytes watchdog: pings come every 15 s, so 40 s of silence means a dead stream.
nonisolated final class LiveClient: Sendable {
    nonisolated struct Tuning: Sendable {
        var backoff: @Sendable (Int) -> Duration = { failures in
            let base = [1.0, 2, 4, 8, 16, 30][min(max(failures - 1, 0), 5)]
            return .milliseconds(Int(base * Double.random(in: 0.8...1.2) * 1000))
        }
        var pollInterval: Duration = .seconds(15)
        /// Start polling /state after this many failed connects in a row.
        var pollAfterFailures = 2
        var watchdog: TimeInterval = 40
        var pingSeconds: Double? = nil
    }

    private let api: APIClient
    private let tuning: Tuning

    init(api: APIClient, tuning: Tuning = .init()) {
        self.api = api
        self.tuning = tuning
    }

    /// Connects when created; cancelling the consuming task (or dropping the stream) closes the connection.
    func events() -> AsyncStream<ServiceEvent> {
        AsyncStream { continuation in
            let task = Task { await run(continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ continuation: AsyncStream<ServiceEvent>.Continuation) async {
        var failures = 0
        var refreshToken = false
        var poller: Task<Void, Never>?
        defer {
            poller?.cancel()
            continuation.finish()
        }

        while !Task.isCancelled {
            continuation.yield(.connection(failures == 0 ? .connecting : .reconnecting(attempt: failures)))
            do {
                var request = try await api.authorizedRequest(
                    "GET", "live", query: tuning.pingSeconds.map { ["ping_seconds": String($0)] } ?? [:],
                    forceRefresh: refreshToken)
                request.timeoutInterval = tuning.watchdog
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                let (bytes, response) = try await api.session.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                refreshToken = status == 401
                guard status == 200 else { throw APIError.from(status: status, body: Data()) }

                var parser = SSEParser()
                var announced = false
                let decoder = JSONCoding.decoder()
                for try await byte in bytes {
                    guard let message = parser.push(byte) else { continue }
                    if !announced {
                        announced = true
                        failures = 0
                        poller?.cancel()
                        poller = nil
                        continuation.yield(.connection(.live))
                    }
                    // A malformed event is skipped; the next state event resyncs everything.
                    if let event = try? LiveEvent.decode(event: message.event, data: Data(message.data.utf8), using: decoder) {
                        continuation.yield(.live(event))
                    }
                }
            } catch {
                if Task.isCancelled { return }
            }

            // The stream ended or failed: back off, and poll /state while it stays down.
            failures += 1
            if failures >= tuning.pollAfterFailures, poller == nil {
                continuation.yield(.connection(.polling))
                poller = Task { [api, interval = tuning.pollInterval] in
                    while !Task.isCancelled {
                        if let state = try? await api.state() { continuation.yield(.live(.state(state))) }
                        try? await Task.sleep(for: interval)
                    }
                }
            }
            do { try await Task.sleep(for: tuning.backoff(failures)) } catch { return }
        }
    }
}
