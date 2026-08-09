import Testing
import Foundation
@testable import SeerSupport

@Suite struct ModelDownloadProgressTests {
    @Test func fractionIsNilWithoutATotal() {
        #expect(ModelDownloadProgress.fraction(completed: 100, total: 0) == nil)
        #expect(ModelDownloadProgress.fraction(completed: 100, total: -1) == nil)
    }

    @Test func fractionClampsToUnitRange() {
        #expect(ModelDownloadProgress.fraction(completed: 50, total: 100) == 0.5)
        #expect(ModelDownloadProgress.fraction(completed: 200, total: 100) == 1.0)
        #expect(ModelDownloadProgress.fraction(completed: -5, total: 100) == 0.0)
    }

    @Test func describesPercentWhenTotalKnown() {
        let s = ModelDownloadProgress.describe(completed: 500_000_000, total: 1_000_000_000)
        #expect(s.contains("50%"))
        #expect(s.contains(" of "))
    }

    @Test func describesBytesOnlyWhenTotalUnknown() {
        let s = ModelDownloadProgress.describe(completed: 500_000_000, total: 0)
        #expect(s.contains("downloaded"))
        #expect(!s.contains("%"))
    }
}
