import Testing
import CoreGraphics
@testable import SeerOverlay

@Suite struct CaretTrackerTests {
    private let r = CGRect(x: 100, y: 100, width: 2, height: 18)

    @Test func cadenceIsFiveHz() {
        #expect(CaretTracker.interval == 0.2)
    }
    @Test func appearWhenWasNil() {
        #expect(CaretTracker.shouldMove(from: nil, to: r) == true)
    }
    @Test func disappearWhenNowNil() {
        #expect(CaretTracker.shouldMove(from: r, to: nil) == true)
    }
    @Test func bothNilNoMove() {
        #expect(CaretTracker.shouldMove(from: nil, to: nil) == false)
    }
    @Test func subThresholdNoMove() {
        let moved = r.offsetBy(dx: 1, dy: 1)
        #expect(CaretTracker.shouldMove(from: r, to: moved) == false)
    }
    @Test func exactlyDeadZoneNoMove() {
        let moved = r.offsetBy(dx: 2, dy: 0)   // boundary: > deadZone is false at == 2
        #expect(CaretTracker.shouldMove(from: r, to: moved) == false)
    }
    @Test func pastThresholdMoves() {
        let moved = r.offsetBy(dx: 3, dy: 0)
        #expect(CaretTracker.shouldMove(from: r, to: moved) == true)
    }
}
