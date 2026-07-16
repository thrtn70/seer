import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
NSLog("[seer] spike booting")
app.run()
