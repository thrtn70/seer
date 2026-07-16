/// Coordinator accept-gesture state (§4.8). `accepting` = mid-insert, before re-anchor resolves.
public enum AcceptState: Sendable, Equatable { case idle, showing, accepting }
