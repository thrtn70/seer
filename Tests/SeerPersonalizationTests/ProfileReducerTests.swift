import Testing
import Foundation
@testable import SeerPersonalization

private func sample(_ completion: String, bundle: String = "com.apple.TextEdit",
                    subrole: String? = nil, t: TimeInterval = 0) -> AcceptedSample {
    AcceptedSample(bundleID: bundle, focusedSubrole: subrole, completion: completion,
                   beforeCaret: "before", timestamp: Date(timeIntervalSince1970: t))
}

@Suite struct ProfileReducerTests {
    @Test func appendsUnderNewBundleKey() {
        let p = ProfileReducer.reduce(.empty, sample: sample("thanks for the update"))
        #expect(p.apps["com.apple.TextEdit"]?.recents.count == 1)
        #expect(p.apps["com.apple.TextEdit"]?.recents.first?.completion == "thanks for the update")
        #expect(p.apps["com.apple.TextEdit"]?.recents.first?.beforeCaret == "before")
    }
    @Test func capsAt200DroppingOldest() {
        var p = StyleProfile.empty
        for i in 0..<(ProfileReducer.recentsCap + 5) {
            p = ProfileReducer.reduce(p, sample: sample("s\(i)", t: TimeInterval(i)))
        }
        let recents = p.apps["com.apple.TextEdit"]?.recents ?? []
        #expect(recents.count == ProfileReducer.recentsCap)
        #expect(recents.first?.completion == "s5")     // oldest 5 dropped
        #expect(recents.last?.completion == "s204")
    }
    @Test func dropsSecureSubroleSamples() {
        // Defense in depth (§6): upstream capture is already fail-closed, re-check here.
        let p = ProfileReducer.reduce(.empty, sample: sample("hunter2", subrole: "AXSecureTextField"))
        #expect(p == .empty)
    }
    @Test func dropsEmptyAndWhitespaceCompletions() {
        let p1 = ProfileReducer.reduce(.empty, sample: sample(""))
        let p2 = ProfileReducer.reduce(.empty, sample: sample("   \n"))
        #expect(p1 == .empty)
        #expect(p2 == .empty)
    }
    @Test func dropPathPreservesExistingCorpus() {
        // A dropped sample must return the corpus UNCHANGED — never wipe it. Both drop
        // guards are exercised against a non-empty base so `return .empty` is caught.
        let base = ProfileReducer.reduce(.empty, sample: sample("keep", bundle: "app.one"))
        #expect(base != .empty)
        let afterSecure = ProfileReducer.reduce(
            base, sample: sample("pw", bundle: "app.one", subrole: "AXSecureTextField"))
        #expect(afterSecure == base)
        let afterBlank = ProfileReducer.reduce(base, sample: sample("   \n", bundle: "app.one"))
        #expect(afterBlank == base)
    }
    @Test func carriesSampleTimestampThrough() {
        // Timestamp is load-bearing for downstream decay weighting; it must survive verbatim.
        let p = ProfileReducer.reduce(.empty, sample: sample("hi", t: 12345))
        #expect(p.apps["com.apple.TextEdit"]?.recents.first?.timestamp
            == Date(timeIntervalSince1970: 12345))
    }
    @Test func trimsPreloadedOverCapInOneReduce() {
        // A pre-loaded over-cap AppProfile must be trimmed all the way to the cap in a single
        // reduce (bulk removeFirst), not one element at a time.
        let over = StyleProfile(apps: ["b": AppProfile(recents: (0..<205).map {
            StoredAcceptance(completion: "s\($0)", beforeCaret: "x",
                             timestamp: Date(timeIntervalSince1970: TimeInterval($0)))
        })])
        let result = ProfileReducer.reduce(over, sample: sample("new", bundle: "b"))
        #expect(result.apps["b"]?.recents.count == ProfileReducer.recentsCap)
        #expect(result.apps["b"]?.recents.last?.completion == "new")
    }
    @Test func keepsAppsIndependent() {
        var p = ProfileReducer.reduce(.empty, sample: sample("a", bundle: "app.one"))
        p = ProfileReducer.reduce(p, sample: sample("b", bundle: "app.two"))
        #expect(p.apps["app.one"]?.recents.count == 1)
        #expect(p.apps["app.two"]?.recents.count == 1)
    }
    @Test func profileRoundTripsThroughCodable() throws {
        let p = ProfileReducer.reduce(.empty, sample: sample("thanks"))
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(StyleProfile.self, from: data)
        #expect(back == p)
    }
}
