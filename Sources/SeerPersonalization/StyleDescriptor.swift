import SeerModel

/// Renders the personalized system string (§7.5): the default instruction + a tone line +
/// optional per-app phrases. nil ⇒ cold start — the caller keeps PromptAssembler's default
/// system so the prompt is byte-identical to the unpersonalized scaffold.
///
/// Byte determinism is load-bearing (this string is the KV-cache prefix): tone values are
/// scaled to Int (String(Int) is locale-free), phrases arrive pre-sorted from the snapshot,
/// and the length cap drops whole trailing phrases, never mid-phrase truncation.
public enum StyleDescriptor {
    /// Character count, not byte count — determinism holds either way (identical input renders
    /// identical output); the cap just bounds the descriptor so it can't crowd the token budget.
    public static let maxLength = 600

    public static func render(snapshot: ProfileSnapshot, bundleID: String) -> String? {
        guard let tone = snapshot.tone(for: bundleID) else { return nil }
        var out = PromptAssembler.defaultSystem
            + "\nMatch the user's writing style — formality \(scale(tone.formality))/10, "
            + "warmth \(scale(tone.warmth))/10, brevity \(scale(tone.brevity))/10."
        let phrases = (snapshot.apps[bundleID]?.phrases ?? []).filter { !$0.contains("<|") }
        if !phrases.isEmpty {
            var line = " The user often writes:"
            var added = false
            for phrase in phrases {
                let candidate = line + (added ? "; " : " ") + "\"\(phrase)\""
                guard out.count + candidate.count + 1 <= maxLength else { break }
                line = candidate
                added = true
            }
            if added { out += line + "." }
        }
        return out
    }

    private static func scale(_ v: Double) -> Int {
        guard v.isFinite else { return 5 }
        return Int((min(max(v, 0), 1) * 10).rounded())
    }
}
