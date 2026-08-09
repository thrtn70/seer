import Testing
@testable import SeerAppKit

@Suite struct ExcludedAppsListModelTests {
    @Test func sortsCaseInsensitivelyByDisplayName() {
        let rows = ExcludedAppsListModel.rows(
            bundleIDs: ["com.z.zed", "com.a.alpha", "com.m.mid"],
            resolveName: { ["com.z.zed": "zed", "com.a.alpha": "Alpha", "com.m.mid": "Mid"][$0] })
        #expect(rows.map(\.displayName) == ["Alpha", "Mid", "zed"])
    }
    @Test func uninstalledFallsBackToBundleID() {
        let rows = ExcludedAppsListModel.rows(bundleIDs: ["com.gone.app"], resolveName: { _ in nil })
        #expect(rows == [ExcludedAppRow(bundleID: "com.gone.app", displayName: "com.gone.app", installed: false)])
    }
    @Test func emptyNameTreatedAsUninstalled() {
        let rows = ExcludedAppsListModel.rows(bundleIDs: ["com.blank.app"], resolveName: { _ in "" })
        #expect(rows.first?.installed == false)
        #expect(rows.first?.displayName == "com.blank.app")
        // Whitespace-only resolves to a visually blank row — same fallback as empty.
        let blank = ExcludedAppsListModel.rows(bundleIDs: ["com.blank.app"], resolveName: { _ in "   " })
        #expect(blank.first?.installed == false)
        #expect(blank.first?.displayName == "com.blank.app")
    }
    @Test func mixedInstalledAndUninstalledSortTogether() {
        let rows = ExcludedAppsListModel.rows(
            bundleIDs: ["com.gone.zzz", "com.here.app"],
            resolveName: { $0 == "com.here.app" ? "TextEdit" : nil })
        #expect(rows.map(\.bundleID) == ["com.gone.zzz", "com.here.app"])   // "com.gone…" < "TextEdit"
    }
    // Four ids, not two: with two, a dropped tiebreak still passes ~1/2 the time because
    // Swift's small-input insertion sort echoes Set iteration order. Four drops that to 1/24.
    @Test func equalNamesTieBreakOnBundleID() {
        let rows = ExcludedAppsListModel.rows(
            bundleIDs: ["com.b.app", "com.d.app", "com.a.app", "com.c.app"],
            resolveName: { _ in "Same" })
        #expect(rows.map(\.bundleID) == ["com.a.app", "com.b.app", "com.c.app", "com.d.app"])
    }
    @Test func emptyInputYieldsNoRows() {
        #expect(ExcludedAppsListModel.rows(bundleIDs: [], resolveName: { _ in nil }).isEmpty)
    }
}
