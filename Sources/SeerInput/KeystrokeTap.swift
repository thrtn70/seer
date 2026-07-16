import CoreGraphics
import Foundation

/// Global keyDown CGEventTap. The callback runs on the MAIN run loop (source added to
/// CFRunLoopGetMain), so `onKeyDown` may read @MainActor state via MainActor.assumeIsolated.
/// `onKeyDown` returns true to SWALLOW the event, false to FORWARD it.
public final class KeystrokeTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    public private(set) var isRunning = false
    public var onKeyDown: ((_ keyCode: Int64, _ flags: CGEventFlags) -> Bool)?

    public init() {}

    public func start() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let cb: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<KeystrokeTap>.fromOpaque(refcon!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let swallow = me.onKeyDown?(code, event.flags) ?? false
            return swallow ? nil : Unmanaged.passUnretained(event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                options: .defaultTap, eventsOfInterest: mask, callback: cb,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { isRunning = false; return }   // Input Monitoring not granted
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    public func pause() { if let tap { CGEvent.tapEnable(tap: tap, enable: false) } }
    public func resume() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    public func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil; tap = nil; isRunning = false
    }
}
