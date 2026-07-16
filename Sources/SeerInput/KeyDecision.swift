import SeerModel

/// What the tap should do with a keyDown, decided purely from the current accept state.
public enum KeyAction: Sendable, Equatable {
    case passThrough        // forward the key; if idle, the coordinator also schedules a suggest
    case accept(AcceptKind) // swallow; run accept
    case dismiss            // swallow (Esc); hide
    case typeOverDismiss    // forward the key AND hide (the user typed a real char)
}

/// Pure swallow-vs-forward classifier. Called synchronously from the tap callback (<1 ms),
/// reading only the accept state.
public enum KeyDecision {
    public static func action(state: AcceptState, keyCode: Int64, hasShift: Bool) -> KeyAction {
        switch state {
        case .idle, .accepting:
            return .passThrough
        case .showing:
            if keyCode == KeyCodes.tab { return .accept(hasShift ? .wholeLine : .nextWord) }
            if keyCode == KeyCodes.escape { return .dismiss }
            return .typeOverDismiss
        }
    }
}
