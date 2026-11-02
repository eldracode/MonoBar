import AppKit
import CoreLocation
import Foundation

final class BarApplicationDelegate: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    private let config = BarConfig.load()
    private let model = BarModel()
    private let locationManager = CLLocationManager()
    private var panels: [BarPanel] = []
    private var eventSocket: EventSocket?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private weak var menuBarScreen: NSScreen?

    func applicationDidFinishLaunching(_ notification: Notification) {
        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestWhenInUseAuthorization()
        }
        model.start()
        panels = NSScreen.screens.map { BarPanel(screen: $0, config: config, model: model) }
        let socket = EventSocket(path: config.socketPath) { [weak model] in model?.aerospace.refresh() }
        socket.start(); eventSocket = socket
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateMenuBarLevel(at: NSEvent.mouseLocation)
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenuBarLevel(at: NSEvent.mouseLocation) }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
    }

    private func updateMenuBarLevel(at point: NSPoint) {
        let hoveredScreen = NSScreen.screens.first { $0.frame.contains(point) }
        var revealedScreen: NSScreen?
        if let current = menuBarScreen, current.frame.contains(point) {
            let menuHeight = max(current.frame.maxY - current.visibleFrame.maxY, 24)
            if point.y >= current.frame.maxY - menuHeight - 10 { revealedScreen = current }
        }
        if revealedScreen == nil, let screen = hoveredScreen {
            let menuHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
            if point.y >= screen.frame.maxY - menuHeight - 2 { revealedScreen = screen }
        }
        menuBarScreen = revealedScreen
        for panel in panels { panel.setMenuBarRevealed(panel.display === revealedScreen) }
    }
}
