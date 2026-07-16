import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AgentDelegate()
app.delegate = delegate
app.run()
