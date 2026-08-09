import Foundation
import SeerModel

/// §7.8 export: derived stats, tone, phrases, and pins by default; raw accepted text
/// (completion + before-caret context + timestamps) ONLY on explicit opt-in. Bytes are
/// deterministic for a given (profile, snapshot, overrides, now) on a given OS release —
/// sorted JSON keys, bundle-sorted app array, whole-second ISO-8601 dates; `schemaVersion`
/// covers evolution. (`.sortedKeys` orders objects, not arrays — the app array is pre-sorted
/// by bundle id here.)
public enum ProfileExport {
    public static let schemaVersion = 1

    public static func json(profile: StyleProfile, snapshot: ProfileSnapshot,
                            overrides: ToneOverrides, includeRawText: Bool,
                            now: Date) throws -> Data {
        let apps = profile.apps.keys.sorted().map { bundle -> AppExport in
            let appSnap = snapshot.apps[bundle]
            let recents = profile.apps[bundle]?.recents ?? []
            return AppExport(bundleID: bundle,
                             sampleCount: appSnap?.sampleCount ?? recents.count,
                             derivedTone: appSnap?.tone.map(ToneExport.init),
                             phrases: appSnap?.phrases ?? [],
                             rawAcceptances: includeRawText
                                ? recents.map(AcceptanceExport.init) : nil)
        }
        let doc = ExportDocument(schemaVersion: Self.schemaVersion,
                                 exportedAt: now,
                                 totalSamples: snapshot.totalSamples,
                                 globalDerivedTone: snapshot.global.map(ToneExport.init),
                                 toneOverrides: OverridesExport(overrides),
                                 includesRawText: includeRawText,
                                 apps: apps)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(doc)
    }
}

// DTOs, not conformances on the domain types: ToneScores stays deliberately non-Codable,
// and the export schema can evolve independently of storage.
struct ExportDocument: Encodable {
    let schemaVersion: Int
    let exportedAt: Date
    let totalSamples: Int
    let globalDerivedTone: ToneExport?
    let toneOverrides: OverridesExport
    let includesRawText: Bool
    let apps: [AppExport]
}
struct ToneExport: Encodable {
    let formality: Double, warmth: Double, brevity: Double
    init(_ t: ToneScores) { formality = t.formality; warmth = t.warmth; brevity = t.brevity }
}
struct OverridesExport: Encodable {
    let formality: Double?, warmth: Double?, brevity: Double?
    init(_ o: ToneOverrides) { formality = o.formality; warmth = o.warmth; brevity = o.brevity }
    // Encode nils explicitly: "formality": null reads as "not pinned" in the exported file,
    // whereas an absent key reads as a schema difference between two exports.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formality, forKey: .formality)
        try c.encode(warmth, forKey: .warmth)
        try c.encode(brevity, forKey: .brevity)
    }
    enum CodingKeys: String, CodingKey { case formality, warmth, brevity }
}
struct AppExport: Encodable {
    let bundleID: String
    let sampleCount: Int
    let derivedTone: ToneExport?
    let phrases: [String]
    let rawAcceptances: [AcceptanceExport]?
}
struct AcceptanceExport: Encodable {
    let completion: String, beforeCaret: String, timestamp: Date
    init(_ a: StoredAcceptance) {
        completion = a.completion; beforeCaret = a.beforeCaret; timestamp = a.timestamp
    }
}
