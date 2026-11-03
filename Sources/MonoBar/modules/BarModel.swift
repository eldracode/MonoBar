import AppKit
import CoreWLAN
import Foundation
import IOBluetooth
import IOKit.ps
import SystemConfiguration

final class BarModel {
    let aerospace = AeroSpace()
    private let wifiClient = CWWiFiClient.shared()
    private let systemConfigStore = SCDynamicStoreCreate(nil, "MonoBar" as CFString, nil, nil)
    private var observers: [() -> Void] = []
    private var timer: Timer?
    private var lastCPU: Double = 0
    private var previousTicks: (UInt32, UInt32, UInt32, UInt32)?

    init() { aerospace.onChange = { [weak self] in self?.notifyChange() } }

    func observe(_ observer: @escaping () -> Void) { observers.append(observer) }

    func start() {
        aerospace.refresh()
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
                var occurrences: [String: Int] = [:]
                let totals = Dictionary(grouping: aerospace.windows, by: \.appName).mapValues(\.count)
                var values = [ModuleValue(text: "│", muted: true)]
                for window in aerospace.windows {
                    if values.count > 1 { values.append(ModuleValue(text: "•", muted: true)) }
                    occurrences[window.appName, default: 0] += 1
                    let label = (totals[window.appName] ?? 0) > 1
                        ? "\(window.appName) \(occurrences[window.appName]!)"
                        : window.appName
                    values.append(ModuleValue(text: label, action: "window:\(window.id)", accent: window.focused))
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
            case "wifi": return [ModuleValue(text: wifiText(), action: "toggle:wifi")]
            case "bluetooth": return bluetoothValues()
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
    }

    private func tick() { lastCPU = cpuUsage(); notifyChange() }
    private func notifyChange() { observers.forEach { $0() } }
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
