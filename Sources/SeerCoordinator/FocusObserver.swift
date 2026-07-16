import AppKit
import ApplicationServices

/// Dismiss trigger for context changes outside the keystroke tap: focused-element changes
/// within the frontmost app (AXObserver) and app switches (NSWorkspace). Re-targets the
/// AX observer when the frontmost app changes (AXObserver is PID-scoped).
@MainActor
public final class FocusObserver {
    public var onInvalidate: (() -> Void)?
    private var observer: AXObserver?
    private(set) var observedPID: pid_t = 0
    private var appElement: AXUIElement?
    private var wsToken: NSObjectProtocol?

    public init() {}

    public func start() {
        guard wsToken == nil else { return }
        wsToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onInvalidate?()
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier ?? 0
                self.retarget(to: pid)
            }
        }
        retarget(to: NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
    }

    public func stop() {
        if let t = wsToken { NSWorkspace.shared.notificationCenter.removeObserver(t); wsToken = nil }
        teardownObserver()
    }

    func retarget(to pid: pid_t) {
        teardownObserver()
        guard pid != 0, pid != ProcessInfo.processInfo.processIdentifier else { return }
        let cb: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let me = Unmanaged<FocusObserver>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { me.onInvalidate?() }
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, cb, &obs) == .success, let obs else { return }
        let appEl = AXUIElementCreateApplication(pid)
        guard AXObserverAddNotification(obs, appEl, kAXFocusedUIElementChangedNotification as CFString,
                                        Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        observer = obs; appElement = appEl; observedPID = pid
    }

    private func teardownObserver() {
        if let obs = observer {
            if let appEl = appElement {
                AXObserverRemoveNotification(obs, appEl, kAXFocusedUIElementChangedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)
        }
        observer = nil; appElement = nil; observedPID = 0
    }
}
