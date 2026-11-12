import AppKit
import CoreLocation
import CoreWLAN
import Foundation
import SystemConfiguration

@MainActor
final class BarModel {
    let config: BarConfig
    let aerospace = AeroSpace()
    let wifiClient = CWWiFiClient.shared()
    let systemConfigStore = SCDynamicStoreCreate(nil, "MonoBar" as CFString, nil, nil)

    private var observers: [() -> Void] = []
    private var timer: Timer?

    var lastCPU: Double = 0
    var previousTicks: (UInt32, UInt32, UInt32, UInt32)?
    var outputVolume: Int?
    var inputVolume: Int?
    var outputMuted: Bool?
    var inputMuted: Bool?
    var weatherLocation: CLLocationCoordinate2D?
    var weatherText = "—"
    var weatherSymbolName = "thermometer.sun"
    var lastWeatherAttempt = Date.distantPast
    var weatherRequest: URLSessionDataTask?
    var vpnState: VPNConnectionState = .disconnected
    var vpnProfileName: String?
    var vpnProfileExists: Bool?
    var vpnStatusRefreshInFlight = false
    var vpnLastStatusCheck = Date.distantPast

    init(config: BarConfig) {
        self.config = config
        aerospace.onChange = { [weak self] in self?.notifyChange() }
    }

    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    func start() {
        aerospace.refresh()
        refreshAudioState()
        refreshVPNStatus(force: true)
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        weatherRequest?.cancel()
        weatherRequest = nil
    }

    func values(for names: [String], screenIndex: Int? = nil) -> [ModuleValue] {
        names.flatMap { name -> [ModuleValue] in
            switch name {
            case "workspaces": return workspaceValues(screenIndex: screenIndex)
            case "title": return windowTitleValues()
            case "clock": return clockValues()
            case "battery": return batteryValues()
            case "cpu": return cpuValues()
            case "ram": return ramValues()
            case "volume": return volumeValues(isInput: false)
            case "mic": return microphoneValues()
            case "wifi": return wifiValues()
            case "bluetooth": return bluetoothValues()
            case "vpn": return vpnValues()
            case "weather": return weatherValues()
            case "music": return musicValues()
            default: return []
            }
        }
    }

    func perform(_ action: String) {
        if action.hasPrefix("workspace:") {
            focusWorkspace(String(action.dropFirst("workspace:".count)))
        } else if action.hasPrefix("window:") {
            focusWindow(String(action.dropFirst("window:".count)))
        } else {
            switch action {
            case "toggle:wifi": toggleWiFi()
            case "toggle:bluetooth": toggleBluetooth()
            case "toggle:mute-output": toggleMute(isInput: false)
            case "toggle:mute-input": toggleMute(isInput: true)
            case "toggle:vpn": toggleVPN()
            default: break
            }
        }
    }

    func tick() {
        lastCPU = cpuUsage()
        refreshAudioState()
        refreshWeather()
        refreshVPNStatus()
        notifyChange()
    }

    func notifyChange() {
        observers.forEach { $0() }
    }
}
