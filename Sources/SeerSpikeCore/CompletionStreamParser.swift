import Foundation

public struct CompletionChunk: Equatable {
    public let text: String
    public let done: Bool
    public init(text: String, done: Bool) { self.text = text; self.done = done }
}

public enum CompletionStreamParser {
    /// Parses one SSE line. Returns nil for keep-alives, blanks, and malformed JSON.
    public static func parse(line: String) -> CompletionChunk? {
        guard line.hasPrefix("data: ") else { return nil }
        let payload = String(line.dropFirst("data: ".count))
        guard let data = payload.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let text = obj["content"] as? String ?? ""
        let done = obj["stop"] as? Bool ?? false
        return CompletionChunk(text: text, done: done)
    }
}
