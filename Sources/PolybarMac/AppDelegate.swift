import AppKit
import Foundation

final class BarApplicationDelegate: NSObject, NSApplicationDelegate {
    private let config = BarConfig.load()
    private let model = BarModel()
    private var panels: [BarPanel] = []
    private var eventSocket: EventSocket?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        panels = NSScreen.screens.map { BarPanel(screen: $0, config: config, model: model) }
        let socket = EventSocket(path: config.socketPath) { [weak model] in model?.aerospace.refresh() }
        socket.start(); eventSocket = socket
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
