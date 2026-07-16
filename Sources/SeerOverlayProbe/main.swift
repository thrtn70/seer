import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // background agent: no Dock icon, no menu bar
let delegate = OverlayProbeDelegate()
app.delegate = delegate
app.run()
