import AppKit
import Foundation

let app = NSApplication.shared
let delegate = BarApplicationDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
