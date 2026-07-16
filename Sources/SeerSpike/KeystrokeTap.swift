import CoreGraphics
import Foundation

final class KeystrokeTap {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onKeyDown: ((_ keyCode: Int64, _ flags: CGEventFlags) -> Bool)?

    func start() {
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
        guard let tap else { NSLog("[seer] tap creation failed — check Input Monitoring"); return }
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func pause() { if let tap { CGEvent.tapEnable(tap: tap, enable: false) } }
    func resume() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }
}
