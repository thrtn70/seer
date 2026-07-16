import Foundation

/// Monotonic elapsed-time stopwatch (DispatchTime-based), immune to wall-clock skew.
/// Use to measure stage latency (e.g. time-to-first-token).
public struct LatencyClock: Sendable {
    private let started: DispatchTime

    /// Starts the clock at the current monotonic instant.
    public init() { self.started = .now() }

    /// Milliseconds elapsed since `init`.
    public func elapsedMilliseconds() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000
    }
}
