/// Main-actor-readable snapshot slot (§3.3 G9): the hot path reads `snapshot` synchronously —
/// no actor hop, no I/O. Publishes are monotonic by version: the store assigns versions
/// inside the actor before any suspension point, so a stale delivery that lost the hop race
/// is rejected here rather than clobbering a newer snapshot.
@MainActor
public final class ProfileCache {
    public private(set) var snapshot: ProfileSnapshot?
    public init() {}
    public func publish(_ snap: ProfileSnapshot) {
        guard snap.version > (snapshot?.version ?? 0) else { return }
        snapshot = snap
    }
}
