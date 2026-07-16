/// Pure accept computation: given the suggestion's word chunks and the accept kind,
/// returns the text to insert and the chunks that remain to keep showing.
public enum AcceptComputation {
    public static func apply(chunks: [String], kind: AcceptKind) -> (toInsert: String, remaining: [String]) {
        guard !chunks.isEmpty else { return ("", []) }
        switch kind {
        case .wholeLine:
            return (chunks.joined(), [])
        case .nextWord:
            var rest = chunks
            let first = rest.removeFirst()
            return (first, rest)
        }
    }
}
