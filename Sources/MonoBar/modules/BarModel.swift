import AppKit
import CoreAudio
import CoreLocation
import CoreWLAN
import Foundation
import IOBluetooth
import IOKit.ps
import SystemConfiguration

@MainActor
final class BarModel {
    private let config: BarConfig
    let aerospace = AeroSpace()
    private let wifiClient = CWWiFiClient.shared()
    private let systemConfigStore = SCDynamicStoreCreate(nil, "MonoBar" as CFString, nil, nil)
    private var observers: [() -> Void] = []
    private var timer: Timer?
    private var lastCPU: Double = 0
    private var previousTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var outputVolume: Int?
    private var inputVolume: Int?
    private var outputMuted: Bool?
    private var inputMuted: Bool?
    private var weatherLocation: CLLocationCoordinate2D?
    private var weatherText = "🌡️ —"
    private var lastWeatherAttempt = Date.distantPast
    private var weatherRequest: URLSessionDataTask?

    init(config: BarConfig) {
        self.config = config
        aerospace.onChange = { [weak self] in self?.notifyChange() }
    }

    var needsWeatherLocation: Bool {
        weatherEnabled && (config.weatherLatitude == nil || config.weatherLongitude == nil)
    }

    func observe(_ observer: @escaping () -> Void) { observers.append(observer) }

    func start() {
        aerospace.refresh()
        outputVolume = readVolume(isInput: false)
        inputVolume = readVolume(isInput: true)
        outputMuted = readMute(isInput: false)
        inputMuted = readMute(isInput: true)
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }

    func values(for names: [String]) -> [ModuleValue] {
        names.flatMap { name -> [ModuleValue] in
            switch name {
            case "workspaces": return aerospace.workspaces.map { ws in
                let state = ws.focused ? "●" : (ws.visible ? "◉" : (ws.occupied ? "•" : "○"))
                return ModuleValue(text: "\(state) \(ws.id)", action: "workspace:\(ws.id)", accent: ws.focused || ws.visible)
            }
            case "title":
                guard !aerospace.windows.isEmpty else { return [] }
                var groups: [(appName: String, windows: [WindowItem])] = []
                var groupIndices: [String: Int] = [:]
                for window in aerospace.windows {
                    if let index = groupIndices[window.appName] {
                        groups[index].windows.append(window)
                    } else {
                        groupIndices[window.appName] = groups.count
                        groups.append((window.appName, [window]))
                    }
                }
                var values = [ModuleValue(text: "│", muted: true)]
                for (groupIndex, group) in groups.enumerated() {
                    if groupIndex > 0 { values.append(ModuleValue(text: "•", muted: true)) }
                    if group.windows.count == 1, let window = group.windows.first {
                        values.append(ModuleValue(text: group.appName, action: "window:\(window.id)", accent: window.focused))
                        continue
                    }
                    values.append(ModuleValue(text: group.appName))
                    values.append(ModuleValue(text: "[", muted: true))
                    for (index, window) in group.windows.enumerated() {
                        if index > 0 { values.append(ModuleValue(text: "•", muted: true)) }
                        values.append(ModuleValue(text: "\(index + 1)", action: "window:\(window.id)", accent: window.focused))
                    }
                    values.append(ModuleValue(text: "]", muted: true))
                }
                return values
            case "clock":
                let now = Date()
                let time = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
                let date = DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .none)
                return [ModuleValue(text: "🕒 \(time)  📅 \(date)")]
            case "battery": return [ModuleValue(text: batteryText())]
            case "cpu": return [ModuleValue(text: String(format: "⚙️ %.0f%%", lastCPU))]
            case "ram": return [ModuleValue(text: memoryText())]
            case "volume": return [ModuleValue(text: outputVolumeText(), action: "toggle:mute-output", scrollAction: "volume:output")]
            case "mic": return [ModuleValue(text: inputVolumeText(), action: "toggle:mute-input", scrollAction: "volume:input")]
            case "wifi": return [ModuleValue(text: wifiText(), action: "toggle:wifi")]
            case "bluetooth": return bluetoothValues()
            case "weather": return [ModuleValue(text: weatherText)]
            case "music": return []
            default: return []
            }
        }
    }

    func perform(_ action: String) {
        if action.hasPrefix("workspace:") { aerospace.focus(String(action.dropFirst("workspace:".count))); aerospace.refresh() }
        else if action.hasPrefix("window:") { aerospace.focusWindow(String(action.dropFirst("window:".count))); aerospace.refresh() }
        else if action == "toggle:wifi" { toggleWiFi() }
        else if action == "toggle:bluetooth" { toggleBluetooth() }
        else if action == "toggle:mute-output" { toggleMute(isInput: false) }
        else if action == "toggle:mute-input" { toggleMute(isInput: true) }
    }

    func adjustVolume(_ target: String, by delta: Int) {
        let isInput = target == "input"
        guard isInput || target == "output", delta != 0,
              let current = readVolume(isInput: isInput),
              let device = defaultAudioDevice(isInput: isInput) else { return }
        let next = min(100, max(0, current + delta))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: isInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var scalar = Float32(next) / 100
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil,
            UInt32(MemoryLayout<Float32>.size), &scalar
        )
        guard status == noErr else { return }
        if isInput { inputVolume = next } else { outputVolume = next }
        notifyChange()
    }

    func updateWeatherLocation(_ location: CLLocationCoordinate2D) {
        weatherLocation = location
        refreshWeather(force: true)
    }

    func weatherLocationUnavailable(_ reason: String) {
        weatherText = "🌡️ \(reason)"
        notifyChange()
    }

    private func tick() {
        lastCPU = cpuUsage()
        outputVolume = readVolume(isInput: false)
        inputVolume = readVolume(isInput: true)
        outputMuted = readMute(isInput: false)
        inputMuted = readMute(isInput: true)
        refreshWeather()
        notifyChange()
    }
    private func notifyChange() { observers.forEach { $0() } }
    private func volumeText(_ level: Int?, icon: String) -> String {
        guard let level else { return "\(icon) —" }
        return "\(icon) \(level)%"
    }
    private func outputVolumeText() -> String {
        volumeText(outputVolume, icon: outputMuted == true ? "🔇" : "🔊")
    }
    private func inputVolumeText() -> String {
        let level = inputVolume.map { "\($0)%" } ?? "—"
        return "🎙️\(inputMuted == true ? " ❌" : "") \(level)"
    }
    private func defaultAudioDevice(isInput: Bool) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
    private func readVolume(isInput: Bool) -> Int? {
        guard let device = defaultAudioDevice(isInput: isInput) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: isInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var scalar: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &scalar)
        guard status == noErr else { return nil }
        return Int((min(1, max(0, scalar)) * 100).rounded())
    }
    private func readMute(isInput: Bool) -> Bool? {
        guard let device = defaultAudioDevice(isInput: isInput) else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: isInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return status == noErr ? muted != 0 : nil
    }
    private func toggleMute(isInput: Bool) {
        guard let device = defaultAudioDevice(isInput: isInput),
              let current = readMute(isInput: isInput) else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: isInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = current ? 0 : 1
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil,
            UInt32(MemoryLayout<UInt32>.size), &muted
        )
        guard status == noErr else { return }
        if isInput { inputMuted = muted != 0 } else { outputMuted = muted != 0 }
        notifyChange()
    }
    private func batteryText() -> String {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef], let source = list.first, let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { return "🔋 —" }
        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        return "🔋 \(current)%\(charging ? " +" : "")"
    }
    private func wifiText() -> String {
        guard let interface = wifiClient.interface() else { return "🛜 —" }
        guard interface.powerOn() else { return "🛜 Off" }
        if let ssid = interface.ssid(), !ssid.isEmpty { return "🛜 \(ssid)" }
        guard let store = systemConfigStore else { return "🛜 —" }
        var interfaces = wifiClient.interfaceNames() ?? []
        if let defaultInterface = wifiClient.interface()?.interfaceName, !interfaces.contains(defaultInterface) {
            interfaces.insert(defaultInterface, at: 0)
        }
        for name in interfaces {
            let key = "State:/Network/Interface/\(name)/AirPort" as CFString
            guard let state = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                  let ssid = (state["SSID_STR"] as? String) ?? (state["SSID"] as? String),
                  !ssid.isEmpty else { continue }
            return "🛜 \(ssid)"
        }
        return "🛜 —"
    }
    private func bluetoothValues() -> [ModuleValue] {
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            return [ModuleValue(text: "", action: "toggle:bluetooth", spacingAfter: 3, symbolName: "fontawesome-bluetooth"), ModuleValue(text: "Off", action: "toggle:bluetooth")]
        }
        let connected = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .first(where: { $0.isConnected() })
        let state = connected?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "On"
        return [ModuleValue(text: "", action: "toggle:bluetooth", spacingAfter: 3, symbolName: "fontawesome-bluetooth"), ModuleValue(text: state, action: "toggle:bluetooth")]
    }
    private func toggleWiFi() {
        guard let interface = wifiClient.interface() else { return }
        do {
            try interface.setPower(!interface.powerOn())
            notifyChange()
        } catch {
            NSLog("MonoBar could not toggle Wi-Fi: %@", error.localizedDescription)
        }
    }
    private func toggleBluetooth() {
        let path = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        guard let path else { return }
        let state = runBlueutil(path: path, arguments: ["--power"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == "0" || state == "1" else { return }
        _ = runBlueutil(path: path, arguments: ["--power", state == "1" ? "0" : "1"])
        notifyChange()
    }
    private func runBlueutil(path: String, arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : ""
        } catch {
            return ""
        }
    }
    private var weatherEnabled: Bool {
        config.weatherProvider == "openweather" && !config.weatherAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private func refreshWeather(force: Bool = false) {
        guard weatherEnabled,
              force || Date().timeIntervalSince(lastWeatherAttempt) >= config.weatherRefreshMinutes * 60 else { return }
        let coordinates: CLLocationCoordinate2D
        if let latitude = config.weatherLatitude, let longitude = config.weatherLongitude {
            coordinates = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else if let weatherLocation {
            coordinates = weatherLocation
        } else {
            return
        }

        let units = config.weatherUnits
        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(coordinates.latitude)),
            URLQueryItem(name: "lon", value: String(coordinates.longitude)),
            URLQueryItem(name: "appid", value: config.weatherAPIKey),
            URLQueryItem(name: "units", value: units)
        ]
        guard let url = components.url else { return }
        lastWeatherAttempt = Date()
        weatherRequest?.cancel()
        weatherRequest = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            if error != nil {
                Task { @MainActor [weak self] in self?.setWeatherStatus("Offline") }
                return
            }
            guard let response = response as? HTTPURLResponse else {
                Task { @MainActor [weak self] in self?.setWeatherStatus("No response") }
                return
            }
            guard response.statusCode == 200 else {
                let message: String
                switch response.statusCode {
                case 401: message = "API key error"
                case 404: message = "City not found"
                case 429: message = "Rate limited"
                default: message = "API \(response.statusCode)"
                }
                Task { @MainActor [weak self] in self?.setWeatherStatus(message) }
                return
            }
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let main = payload["main"] as? [String: Any],
                  let temperature = (main["temp"] as? NSNumber)?.doubleValue,
                  let condition = (payload["weather"] as? [[String: Any]])?.first,
                  let code = (condition["id"] as? NSNumber)?.intValue else {
                Task { @MainActor [weak self] in self?.setWeatherStatus("Bad response") }
                return
            }
            let icon = condition["icon"] as? String ?? ""
            let symbol = Self.weatherSymbol(code: code, icon: icon)
            let unit = units == "metric" ? "°C" : (units == "imperial" ? "°F" : " K")
            let summary = "\(symbol) \(Int(temperature.rounded()))\(unit)"
            Task { @MainActor [weak self] in
                self?.weatherText = summary
                self?.weatherRequest = nil
                self?.notifyChange()
            }
        }
        weatherRequest?.resume()
    }
    private func setWeatherStatus(_ status: String) {
        weatherText = "🌡️ \(status)"
        weatherRequest = nil
        notifyChange()
    }
    private static func weatherSymbol(code: Int, icon: String) -> String {
        switch code {
        case 200..<300: return "⛈️"
        case 300..<400: return "🌦️"
        case 500..<600: return "🌧️"
        case 600..<700: return "❄️"
        case 700..<800: return "🌫️"
        case 800: return icon.hasSuffix("n") ? "🌙" : "☀️"
        case 801: return icon.hasSuffix("n") ? "☁️" : "🌤️"
        default: return "☁️"
        }
    }
    private func memoryText() -> String {
        var stats = vm_statistics64(); var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
        guard result == KERN_SUCCESS else { return "▤ —" }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return "▤ —" }
        let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * UInt64(pageSize)
        return String(format: "▤ %.1fG", Double(used) / 1_073_741_824)
    }
    private func cpuUsage() -> Double {
        var info = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        guard result == KERN_SUCCESS else { return 0 }
        let user = info.cpu_ticks.0, system = info.cpu_ticks.1, idle = info.cpu_ticks.2, nice = info.cpu_ticks.3
        defer { previousTicks = (user, system, idle, nice) }
        guard let old = previousTicks else { return 0 }
        let total = Double(user &- old.0 + system &- old.1 + idle &- old.2 + nice &- old.3)
        return total == 0 ? 0 : 100 * Double(user &- old.0 + system &- old.1 + nice &- old.3) / total
    }
}
