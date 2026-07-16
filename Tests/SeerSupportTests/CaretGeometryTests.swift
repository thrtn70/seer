import Testing
import CoreGraphics
@testable import SeerSupport

@Suite struct CaretGeometryTests {
    @Test func flipYInvertsAboutPrimaryHeight() {
        #expect(CaretGeometry.flipY(axTop: 100, height: 20, primaryHeight: 1000) == 880)
    }
    @Test func validRectOnScreenIsValid() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(CaretGeometry.isValid(CGRect(x: 10, y: 10, width: 2, height: 18), primaryFrame: screen))
    }
    @Test func emptyRectInvalid() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(!CaretGeometry.isValid(CGRect(x: 10, y: 10, width: 0, height: 18), primaryFrame: screen))
    }
    @Test func oversizedRectInvalid() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(!CaretGeometry.isValid(CGRect(x: 0, y: 0, width: 50_000, height: 18), primaryFrame: screen))
    }
    @Test func offscreenRectInvalid() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        #expect(!CaretGeometry.isValid(CGRect(x: 9000, y: 9000, width: 2, height: 18), primaryFrame: screen))
    }
    @Test func negativeDimensionRectInvalid() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        // CGRect allows negative width/height at construction; isValid must reject them.
        #expect(!CaretGeometry.isValid(CGRect(x: 10, y: 10, width: -2, height: 18), primaryFrame: screen))
    }
}
