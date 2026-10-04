import Foundation
import Testing
@testable import Gummi

@Suite("Live client")
struct LiveClientTests {
    nonisolated final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func next() -> Int { lock.withLock { value += 1; return value } }
    }

    private static let fast = LiveClient.Tuning(backoff: { _ in .milliseconds(10) }, pollInterval: .milliseconds(20),
                                                pollAfterFailures: 2, watchdog: 5, pingSeconds: nil)

    private static func sse() throws -> Data {
        let state = String(decoding: try Fixtures.data("state_full"), as: UTF8.self).replacingOccurrences(of: "\n", with: "")
        let card = String(decoding: try Fixtures.data("card_meal_due"), as: UTF8.self).replacingOccurrences(of: "\n", with: "")
        return Data(": connected\n\nevent: state\ndata: \(state)\n\nevent: card\ndata: \(card)\n\nevent: mood\ndata: {\"mood\":\"proud\"}\n\n".utf8)
    }

    /// Collects events until `count` live events have arrived.
    private func collect(_ service: LiveGummiService, liveEvents count: Int) async -> [ServiceEvent] {
        var collected: [ServiceEvent] = []
        var live = 0
        for await event in service.events() {
            collected.append(event)
            if case .live = event { live += 1 }
            if live >= count { break }
        }
        return collected
    }

    @Test func connectsParsesAndAnnouncesLive() async throws {
        let body = try Self.sse()
        let session = StubURLProtocol.session { request in
            if request.url?.path == "/oidc/v1/token" { return (200, TestConfig.token("t")) }
            #expect(request.url?.path == "/api/v1/live")
            #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
            return (200, body)
        }
        let service = LiveGummiService(config: TestConfig.config, session: session, tuning: Self.fast)
        let events = await collect(service, liveEvents: 3)
        guard case .connection(.connecting) = events.first else {
            Issue.record("first event should be connecting")
            return
        }
        guard case .connection(.live) = events[1], case .live(.state(let state)) = events[2] else {
            Issue.record("expected live, then state: \(events)")
            return
        }
        #expect(state.actingAs == "p_012")
        guard case .live(.card(let card)) = events[3], case .live(.mood(.proud)) = events[4] else {
            Issue.record("expected card then mood")
            return
        }
        #expect(card.pendingDueId == "d_1")
    }

    @Test func refreshesTheTokenAfterA401OnLive() async throws {
        let body = try Self.sse()
        let tokens = Counter()
        let session = StubURLProtocol.session { request in
            if request.url?.path == "/oidc/v1/token" { return (200, TestConfig.token("t\(tokens.next())")) }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer t1" ? (401, Data()) : (200, body)
        }
        let service = LiveGummiService(config: TestConfig.config, session: session, tuning: Self.fast)
        let events = await collect(service, liveEvents: 1)
        #expect(events.contains { if case .connection(.reconnecting(attempt: 1)) = $0 { true } else { false } })
        #expect(events.contains { if case .live(.state) = $0 { true } else { false } })
    }

    @Test func pollsStateWhileLiveIsDown() async throws {
        let state = try Fixtures.data("state_null")
        let session = StubURLProtocol.session { request in
            switch request.url?.path {
            case "/oidc/v1/token": (200, TestConfig.token("t"))
            case "/api/v1/live": (503, Data(#"{"error":{"code":"warming_up","message":"loading"}}"#.utf8))
            default: (200, state)
            }
        }
        let service = LiveGummiService(config: TestConfig.config, session: session, tuning: Self.fast)
        let events = await collect(service, liveEvents: 1)
        #expect(events.contains { if case .connection(.polling) = $0 { true } else { false } })
        guard case .live(.state(let polled)) = events.last else {
            Issue.record("expected a polled state")
            return
        }
        #expect(polled.following == nil)
    }
}
