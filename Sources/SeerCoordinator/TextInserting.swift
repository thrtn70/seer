import SeerInput
import SeerInsertion

/// Insertion seam so the coordinator is testable with a spy. Production uses PasteStrategy.
@MainActor
public protocol TextInserting: AnyObject {
    func insert(_ text: String, gate: KeystrokeGate)
}

/// The KeystrokeTap satisfies the insertion gate (it already pauses/resumes the tap).
extension KeystrokeTap: KeystrokeGate {}

/// Production inserter: paste strategy on the general pasteboard.
@MainActor
public final class PasteInserter: TextInserting {
    public init() {}
    public func insert(_ text: String, gate: KeystrokeGate) {
        PasteStrategy.insert(text, gate: gate)
    }
}
