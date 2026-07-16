/// Pure UTF-16-aware split of a field's value at the caret. AX reports caret/selection
/// offsets in UTF-16 code units, so we index by UTF-16 and convert back to String indices
/// (guards against splitting an astral codepoint — the Phase 0 caret-slicing fix).
public enum TextSlice {
    public static func aroundCaret(value: String, caretUTF16: Int) -> (before: String, after: String) {
        let utf16 = value.utf16
        let clamped = max(0, min(caretUTF16, utf16.count))
        guard let i16 = utf16.index(utf16.startIndex, offsetBy: clamped, limitedBy: utf16.endIndex),
              let sIdx = i16.samePosition(in: value) else {
            return (value, "")
        }
        return (String(value[..<sIdx]), String(value[sIdx...]))
    }
}
