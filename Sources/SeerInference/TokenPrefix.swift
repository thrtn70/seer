public enum TokenPrefix {
    /// Length of the longest shared prefix between two token sequences.
    /// Used to decide how much cached KV state to keep when the prompt changes.
    public static func commonLength(_ a: [Int32], _ b: [Int32]) -> Int {
        let n = min(a.count, b.count)
        var i = 0
        while i < n, a[i] == b[i] { i += 1 }
        return i
    }
}
