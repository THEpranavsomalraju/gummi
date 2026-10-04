import Foundation
import Testing
@testable import Gummi

@Suite("API client")
struct APIClientTests {
    /// Counts calls from inside a stub handler.
    nonisolated final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        func bump(_ key: String) -> Int { lock.withLock { counts[key, default: 0] += 1; return counts[key]! } }
        func count(_ key: String) -> Int { lock.withLock { counts[key, default: 0] } }
    }

    @Test func sendsBearerTokenAndUserIdAndDecodesState() async throws {
        let session = StubURLProtocol.session { request in
            if request.url?.path == "/oidc/v1/token" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic \(Data("client:secret".utf8).base64EncodedString())")
                return (200, TestConfig.token("t1"))
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t1")
            #expect(request.value(forHTTPHeaderField: "X-User-Id") == "u_test")
            #expect(request.url?.path == "/api/v1/state")
            return (200, (try? Fixtures.data("state_full")) ?? Data())
        }
        let state = try await APIClient(config: TestConfig.config, session: session).state()
        #expect(state.actingAs == "p_012")
    }

    @Test func refreshesTheTokenOnceAfterA401() async throws {
        let counter = Counter()
        let session = StubURLProtocol.session { request in
            if request.url?.path == "/oidc/v1/token" {
                return (200, TestConfig.token("t\(counter.bump("token"))"))
            }
            _ = counter.bump("api")
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer t1"
                ? (401, Data())
                : (200, (try? Fixtures.data("live_health")) ?? Data())
        }
        let health = try await APIClient(config: TestConfig.config, session: session).health()
        #expect(health.mode == .live)
        #expect(counter.count("token") == 2)
        #expect(counter.count("api") == 2)
    }

    @Test func persistent401IsUnauthorized() async throws {
        let session = StubURLProtocol.session { request in
            request.url?.path == "/oidc/v1/token" ? (200, TestConfig.token("t")) : (401, Data())
        }
        await #expect(throws: APIError.unauthorized) {
            try await APIClient(config: TestConfig.config, session: session).state()
        }
    }

    @Test func contractErrorShapeBecomesTypedError() async throws {
        let session = StubURLProtocol.session { request in
            if request.url?.path == "/oidc/v1/token" { return (200, TestConfig.token("t")) }
            #expect(request.httpMethod == "POST")
            return (409, Data(#"{"error":{"code":"due_already_logged","message":"d_1 was logged already"}}"#.utf8))
        }
        do {
            _ = try await APIClient(config: TestConfig.config, session: session).logDueMeal(dueId: "d_1")
            Issue.record("expected an error")
        } catch let error as APIError {
            #expect(error == .http(status: 409, code: "due_already_logged", message: "d_1 was logged already"))
            #expect(error.code == "due_already_logged")
        }
    }

    @Test func nonJSONErrorBodyStillMaps() {
        let error = APIError.from(status: 502, body: Data("Bad Gateway".utf8))
        #expect(error == .http(status: 502, code: "http_502", message: "Bad Gateway"))
    }

    @Test func requestBodiesMatchTheContract() async throws {
        let session = StubURLProtocol.session { request in
            if request.url?.path == "/oidc/v1/token" { return (200, TestConfig.token("t")) }
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            switch request.url?.path {
            case "/api/v1/follow":
                #expect(body?.keys.contains("user_id") == true)
                #expect(body?["user_id"] is NSNull)
                return (200, (try? Fixtures.data("state_null")) ?? Data())
            case "/api/v1/stream/start":
                #expect(body?["start_at"] as? String == "day4T05:00")
                #expect(body?["delay_minutes"] as? Int == 60)
                return (200, (try? Fixtures.data("live_stream_status")) ?? Data())
            default:
                return (404, Data(#"{"error":{"code":"not_found","message":"no route"}}"#.utf8))
            }
        }
        let client = APIClient(config: TestConfig.config, session: session)
        let state = try await client.follow(nil)
        #expect(state.following == nil)
        let stream = try await client.startStream()
        #expect(stream.participants == 15)
    }

    @Test func feedWrapperDecodes() throws {
        let feed = try Fixtures.decode(FeedResponse.self, "feed")
        #expect(feed.cards.count == 4)
    }

    /// Talks to the deployed App. Runs only with TEST_RUNNER_GUMMI_LIVE_TESTS=1 and secrets configured.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GUMMI_LIVE_TESTS"] == "1"))
    func liveSmokeAgainstTheDeployedApp() async throws {
        let client = APIClient(config: try AppConfig.load())
        let health = try await client.health()
        #expect(health.status == "ok")
        let state = try await client.state()
        #expect(state.userId == "u_mahil")
    }
}
