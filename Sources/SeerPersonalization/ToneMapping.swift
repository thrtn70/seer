/// §7.4: temperature = clamp(0.25 + 0.20·(1−brevity), 0.2, 0.5). Applies only when the user
/// enables "Auto (match my style)" — threshold gating (tone present at all) is the caller's
/// job via ProfileSnapshot.tone(for:).
public enum ToneMapping {
    public static func autoTemperature(brevity: Double) -> Double {
        let b = brevity.isFinite ? min(max(brevity, 0), 1) : 0.5
        return min(max(0.25 + 0.20 * (1 - b), 0.2), 0.5)
    }
}
