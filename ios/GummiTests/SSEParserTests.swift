import Foundation
import Testing
@testable import Gummi

@Suite("SSE parser")
struct SSEParserTests {
    private func parse(_ text: String, chunkSize: Int? = nil) -> [SSEMessage] {
        var parser = SSEParser()
        let bytes = Array(text.utf8)
        guard let chunkSize else { return parser.push(bytes) }
        return stride(from: 0, to: bytes.count, by: chunkSize).flatMap {
            parser.push(bytes[$0..<min($0 + chunkSize, bytes.count)])
        }
    }

    @Test func capturedLiveStreamFromTheDeployedApp() throws {
        let text = String(decoding: try Fixtures.data("live_sse_capture", ext: "txt"), as: UTF8.self)
        #expect(text.hasPrefix(": connected"))
        let messages = parse(text)
        #expect(messages.first?.event == "state")
        #expect(messages.contains { $0.event == "ping" })
        let event = try LiveEvent.decode(event: messages[0].event, data: Data(messages[0].data.utf8))
        guard case .state(let state) = event else {
            Issue.record("first event is not state")
            return
        }
        #expect(state.userId == "u_mahil")
    }

    @Test func blankLineEndsAnEventAndCommentsAreIgnored() {
        let messages = parse(": connected\n\nevent: mood\ndata: {\"mood\":\"proud\"}\n\nevent: ping\ndata: {}\n\n")
        #expect(messages == [SSEMessage(event: "mood", data: #"{"mood":"proud"}"#), SSEMessage(event: "ping", data: "{}")])
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func lineEndings(_ newline: String) {
        let text = ["event: card", "data: {\"a\":1}", "", "data: x", "", ""].joined(separator: newline)
        #expect(parse(text) == [SSEMessage(event: "card", data: #"{"a":1}"#), SSEMessage(event: "message", data: "x")])
    }

    @Test(arguments: [1, 2, 3, 7, 64])
    func chunkBoundariesDoNotMatter(_ size: Int) {
        let text = "event: grade\r\ndata: {\"g\":\"é\"}\r\n\r\nevent: ping\ndata: {}\n\n"
        #expect(parse(text, chunkSize: size) == parse(text))
        #expect(parse(text, chunkSize: size).count == 2)
    }

    @Test func multiLineDataJoinsWithNewlines() {
        #expect(parse("data: one\ndata: two\ndata:three\n\n") == [SSEMessage(event: "message", data: "one\ntwo\nthree")])
    }

    @Test func eventWithoutDataIsNotDispatched() {
        #expect(parse("event: state\n\n").isEmpty)
        #expect(parse("event: state\ndata: {}").isEmpty)
    }

    @Test func liveEventDecoding() throws {
        #expect(try LiveEvent.decode(event: "mood", data: Data(#"{"mood":"proud"}"#.utf8)) == .mood(.proud))
        #expect(try LiveEvent.decode(event: "ping", data: Data(#"{"t":"2026-10-03T22:07:23-04:00"}"#.utf8))
            == .ping(JSONCoding.parseDate("2026-10-03T22:07:23-04:00")))
        #expect(try LiveEvent.decode(event: "confetti", data: Data("{}".utf8)) == .unknown(name: "confetti"))
        let card = try LiveEvent.decode(event: "card", data: Fixtures.data("card_meal_due"))
        guard case .card(let decoded) = card else {
            Issue.record("not a card")
            return
        }
        #expect(decoded.pendingDueId == "d_1")
    }
}
