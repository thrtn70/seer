import Testing
import Foundation
import SeerModel
@testable import SeerPersonalization

private let exportNow = Date(timeIntervalSince1970: 1_752_800_000)
/// Distinct word pairs per acceptance: no n-gram repeats, so PhraseExtractor yields NO
/// phrases — the redaction test can assert raw-string absence without a derived phrase
/// echoing the same words back into the default export. Timestamps sit just before
/// exportNow so decay weights stay ~1 (ancient timestamps decay to ~0 and would zero out
/// tone/phrase derivation entirely).
private func corpusProfile() -> StyleProfile {
    let words = ["alpha bravo", "charlie delta", "echo foxtrot", "golf hotel", "india juliett"]
    var apps: [String: AppProfile] = [:]
    apps["app.one"] = AppProfile(recents: words.enumerated().map { i, w in
        StoredAcceptance(completion: w, beforeCaret: "CTXSENTINEL\(i)",
                         timestamp: exportNow.addingTimeInterval(Double(-i)))
    })
    apps["app.two"] = AppProfile(recents: [
        StoredAcceptance(completion: "kilo lima", beforeCaret: "CTXSENTINEL9",
                         timestamp: exportNow.addingTimeInterval(-9)),
    ])
    return StyleProfile(apps: apps)
}

@Suite struct ProfileExportTests {
    @Test func defaultExportOmitsRawTextEverywhere() throws {
        let profile = corpusProfile()
        let snap = ProfileSnapshot.build(from: profile, now: exportNow, version: 3, overrides: .neutral)
        let data = try ProfileExport.json(profile: profile, snapshot: snap, overrides: .neutral,
                                          includeRawText: false, now: exportNow)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("alpha bravo"))
        #expect(!text.contains("CTXSENTINEL"))
        #expect(text.contains("app.one"))                 // derived stats still present
        #expect(text.contains("\"sampleCount\""))
        #expect(text.contains("\"includesRawText\" : false"))
    }
    @Test func optInIncludesRawText() throws {
        let profile = corpusProfile()
        let snap = ProfileSnapshot.build(from: profile, now: exportNow, version: 3, overrides: .neutral)
        let data = try ProfileExport.json(profile: profile, snapshot: snap, overrides: .neutral,
                                          includeRawText: true, now: exportNow)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("alpha bravo"))
        #expect(text.contains("CTXSENTINEL0"))
    }
    @Test func phrasesAreExportedAsDerivedDataEvenWhenRedacted() throws {
        // Phrases are §7.8-sanctioned derived stats: repeated completions produce one, and it
        // appears in the DEFAULT export even though the raw acceptances do not.
        var apps: [String: AppProfile] = [:]
        apps["app.rep"] = AppProfile(recents: (0..<3).map { i in
            StoredAcceptance(completion: "thanks for the update", beforeCaret: "c",
                             timestamp: exportNow.addingTimeInterval(Double(-i)))
        })
        let profile = StyleProfile(apps: apps)
        let snap = ProfileSnapshot.build(from: profile, now: exportNow, version: 1, overrides: .neutral)
        let data = try ProfileExport.json(profile: profile, snapshot: snap, overrides: .neutral,
                                          includeRawText: false, now: exportNow)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("thanks for"))              // the derived phrase
        #expect(!text.contains("\"completion\""))          // but no raw acceptance objects
    }
    @Test func deterministicAcrossDictionaryInsertionOrder() throws {
        var apps1: [String: AppProfile] = [:]
        var apps2: [String: AppProfile] = [:]
        let names = (0..<8).map { "app.export\($0)" }
        func recents(_ n: String) -> [StoredAcceptance] {
            [StoredAcceptance(completion: "text for \(n)", beforeCaret: "b",
                              timestamp: exportNow.addingTimeInterval(-1))]
        }
        for n in names { apps1[n] = AppProfile(recents: recents(n)) }
        for n in names.reversed() { apps2[n] = AppProfile(recents: recents(n)) }
        let p1 = StyleProfile(apps: apps1), p2 = StyleProfile(apps: apps2)
        let s1 = ProfileSnapshot.build(from: p1, now: exportNow, version: 5, overrides: .neutral)
        let s2 = ProfileSnapshot.build(from: p2, now: exportNow, version: 5, overrides: .neutral)
        let d1 = try ProfileExport.json(profile: p1, snapshot: s1, overrides: .neutral,
                                        includeRawText: true, now: exportNow)
        let d2 = try ProfileExport.json(profile: p2, snapshot: s2, overrides: .neutral,
                                        includeRawText: true, now: exportNow)
        #expect(d1 == d2)
    }
    @Test func overridesAndSchemaVersionAppear() throws {
        let ov = ToneOverrides(formality: nil, warmth: 0.5, brevity: nil)
        let data = try ProfileExport.json(profile: .empty,
                                          snapshot: .build(from: .empty, now: exportNow,
                                                           version: 1, overrides: ov),
                                          overrides: ov, includeRawText: false, now: exportNow)
        let doc = try decodeDoc(data)
        #expect(doc.schemaVersion == 1)
        #expect(doc.toneOverrides.warmth == 0.5)
        #expect(doc.toneOverrides.formality == nil)
        #expect(doc.totalSamples == 0)
        #expect(doc.apps.isEmpty)
        // Explicit-null contract: an unpinned axis must appear as `null`, not as an absent
        // key (the decode above can't tell the two apart — this byte assertion can).
        #expect(String(decoding: data, as: UTF8.self).contains("\"formality\" : null"))
    }
    @Test func exportValuesReflectTheCorpus() throws {
        // Value-level assertions on a non-empty corpus: kills hardcoded-zero mutants on
        // totalSamples/sampleCount, a lying includesRawText flag, an unstamped exportedAt,
        // and pins the deterministic bundle-sorted app order explicitly.
        let profile = corpusProfile()
        let snap = ProfileSnapshot.build(from: profile, now: exportNow, version: 3, overrides: .neutral)
        let data = try ProfileExport.json(profile: profile, snapshot: snap, overrides: .neutral,
                                          includeRawText: true, now: exportNow)
        let doc = try decodeDoc(data)
        #expect(doc.totalSamples == 6)
        #expect(doc.apps.map(\.bundleID) == ["app.one", "app.two"])
        #expect(doc.apps.map(\.sampleCount) == [5, 1])
        #expect(doc.includesRawText == true)
        #expect(doc.exportedAt == exportNow)
    }
    @Test func derivedToneExportsUnswappedAxes() throws {
        let snap = ProfileSnapshot(version: 1, totalSamples: 40,
                                   global: ToneScores(formality: 0.1, warmth: 0.2, brevity: 0.3),
                                   apps: [:], overrides: .neutral)
        let data = try ProfileExport.json(profile: .empty, snapshot: snap, overrides: .neutral,
                                          includeRawText: false, now: exportNow)
        let doc = try decodeDoc(data)
        #expect(doc.globalDerivedTone?.formality == 0.1)
        #expect(doc.globalDerivedTone?.warmth == 0.2)
        #expect(doc.globalDerivedTone?.brevity == 0.3)
    }
    @Test func adversarialOverridesCannotPoisonEncoding() throws {
        // JSONEncoder throws on non-finite Doubles; ToneOverrides sanitizes at construction,
        // so the encoder can never see one. This pins that chain.
        let o = ToneOverrides(formality: .nan, warmth: .infinity, brevity: 0.5)
        let data = try ProfileExport.json(profile: .empty,
                                          snapshot: .build(from: .empty, now: exportNow,
                                                           version: 1, overrides: o),
                                          overrides: o, includeRawText: false, now: exportNow)
        #expect(!data.isEmpty)
    }
}

/// Minimal decode mirror — deliberately NOT the production DTOs, so a renamed JSON key is a
/// test failure, not a silently co-evolving pass.
private struct TestDoc: Decodable {
    struct Tone: Decodable { let formality: Double?; let warmth: Double?; let brevity: Double? }
    struct App: Decodable { let bundleID: String; let sampleCount: Int }
    let schemaVersion: Int
    let exportedAt: Date
    let totalSamples: Int
    let globalDerivedTone: Tone?
    let toneOverrides: Tone
    let includesRawText: Bool
    let apps: [App]
}
private func decodeDoc(_ data: Data) throws -> TestDoc {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(TestDoc.self, from: data)
}
