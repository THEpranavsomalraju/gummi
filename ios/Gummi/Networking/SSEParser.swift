import Foundation

nonisolated struct SSEMessage: Equatable, Sendable {
    let event: String
    let data: String
}

/// Incremental server-sent events parser that works byte by byte.
/// URLSession.AsyncBytes.lines drops blank lines, and blank lines are what end an SSE event,
/// so the live channel feeds raw bytes here instead.
/// Handles LF, CR, and CRLF line endings, comment lines (": connected"), and multi-line data.
nonisolated struct SSEParser {
    private var line: [UInt8] = []
    private var lastWasCR = false
    private var eventName = ""
    private var dataLines: [String] = []

    /// Feeds one byte. Returns a message when that byte completes an event.
    mutating func push(_ byte: UInt8) -> SSEMessage? {
        switch byte {
        case 0x0D:
            lastWasCR = true
            return endLine()
        case 0x0A:
            if lastWasCR {
                lastWasCR = false
                return nil
            }
            return endLine()
        default:
            lastWasCR = false
            line.append(byte)
            return nil
        }
    }

    mutating func push<S: Sequence>(_ bytes: S) -> [SSEMessage] where S.Element == UInt8 {
        bytes.compactMap { push($0) }
    }

    private mutating func endLine() -> SSEMessage? {
        defer { line.removeAll(keepingCapacity: true) }
        guard !line.isEmpty else { return dispatch() }
        let text = String(decoding: line, as: UTF8.self)
        if text.hasPrefix(":") { return nil }
        let field: Substring
        var value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            value = text[text.index(after: colon)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = Substring(text)
            value = ""
        }
        switch field {
        case "event": eventName = String(value)
        case "data": dataLines.append(String(value))
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> SSEMessage? {
        defer {
            eventName = ""
            dataLines.removeAll()
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEMessage(event: eventName.isEmpty ? "message" : eventName, data: dataLines.joined(separator: "\n"))
    }
}
