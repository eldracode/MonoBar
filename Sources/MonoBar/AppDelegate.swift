import AppKit
import CoreLocation
import Foundation

@MainActor
final class BarApplicationDelegate: NSObject, NSApplicationDelegate, @preconcurrency CLLocationManagerDelegate {
    private let config = BarConfig.load()
    private lazy var model = BarModel(config: config)
    private let locationManager = CLLocationManager()
    private var panels: [BarPanel] = []
    private var eventSocket: EventSocket?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var fullscreenTimer: Timer?
    private var weatherLocationTimer: Timer?
    private var spaceObserver: NSObjectProtocol?
    private weak var menuBarScreen: NSScreen?
    private var didStart = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !didStart else { return }
        didStart = true
        locationManager.delegate = self
        if locationManager.authorizationStatus == .notDetermined {
            NSApp.activate(ignoringOtherApps: true)
            locationManager.requestWhenInUseAuthorization()
        } else {
            requestWeatherLocationIfNeeded()
        }
        model.start()
        panels = NSScreen.screens.map { BarPanel(screen: $0, config: config, model: model) }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateFullscreenVisibility(forceShow: true) }
        }
        let fullscreenTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateFullscreenVisibility() }
        }
        RunLoop.main.add(fullscreenTimer, forMode: .common)
        self.fullscreenTimer = fullscreenTimer
        updateFullscreenVisibility(forceShow: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateFullscreenVisibility(forceShow: true)
        }
        let weatherLocationTimer = Timer(timeInterval: config.weatherRefreshMinutes * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.requestWeatherLocationIfNeeded() }
        }
        RunLoop.main.add(weatherLocationTimer, forMode: .common)
        self.weatherLocationTimer = weatherLocationTimer
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
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        fullscreenTimer?.invalidate()
        weatherLocationTimer?.invalidate()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestWeatherLocationIfNeeded()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        model.updateWeatherLocation(location.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        model.weatherLocationUnavailable("Location unavailable")
    }

    private func requestWeatherLocationIfNeeded() {
        guard model.needsWeatherLocation else { return }
        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
            locationManager.requestLocation()
        case .denied, .restricted:
            model.weatherLocationUnavailable("Location off")
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            model.weatherLocationUnavailable("No location")
        }
    }

    private func updateFullscreenVisibility(forceShow: Bool = false) {
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let mainScreen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
        } ?? NSScreen.main
        let mainTop = mainScreen?.frame.maxY ?? NSScreen.screens.map(\.frame.maxY).max() ?? 0
        var fullscreenScreens = Set<ObjectIdentifier>()

        for window in windows {
            let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            let ownerName = window[kCGWindowOwnerName as String] as? String ?? ""
            let windowName = window[kCGWindowName as String] as? String ?? ""
            guard let ownerPID, ownerPID > 0,
                  ownerPID != ProcessInfo.processInfo.processIdentifier,
                  ownerName != "Window Server", ownerName != "Dock", ownerName != "SystemUIServer",
                  !(ownerName == "Finder" && windowName == "Desktop"),
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { continue }

            let appKitBounds = CGRect(x: bounds.minX, y: mainTop - bounds.maxY, width: bounds.width, height: bounds.height)
            for screen in NSScreen.screens {
                let frame = screen.frame
                guard frame.width > 0, frame.height > 0,
                      abs(appKitBounds.width - frame.width) <= frame.width * 0.03,
                      abs(appKitBounds.height - frame.height) <= frame.height * 0.03 else { continue }
                let intersection = frame.intersection(appKitBounds)
                let visibleFraction = intersection.width * intersection.height / (frame.width * frame.height)
                if visibleFraction >= 0.97 { fullscreenScreens.insert(ObjectIdentifier(screen)) }
            }
        }

        if let menuBarScreen, fullscreenScreens.contains(ObjectIdentifier(menuBarScreen)) { self.menuBarScreen = nil }
        for panel in panels {
            let isFullscreen = fullscreenScreens.contains(ObjectIdentifier(panel.display))
            if isFullscreen { panel.setMenuBarRevealed(false) }
            panel.setHiddenForFullscreen(isFullscreen)
            if forceShow && !isFullscreen { panel.showInCurrentSpace() }
        }
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
