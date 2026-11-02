import AppKit
import CoreWLAN
import Foundation
import IOKit.ps
import SystemConfiguration

final class BarModel {
    let aerospace = AeroSpace()
    private let wifiClient = CWWiFiClient.shared()
    private let systemConfigStore = SCDynamicStoreCreate(nil, "PolybarMac" as CFString, nil, nil)
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
                guard !aerospace.title.isEmpty else { return [] }
                let divider = aerospace.workspaces.isEmpty ? [] : [ModuleValue(text: "│", muted: true)]
                return divider + [ModuleValue(text: aerospace.title)]
            case "clock":
                let now = Date()
                let time = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
                let date = DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .none)
                return [ModuleValue(text: "🕒 \(time)  📅 \(date)")]
            case "battery": return [ModuleValue(text: batteryText())]
            case "cpu": return [ModuleValue(text: String(format: "⚙️ %.0f%%", lastCPU))]
            case "ram": return [ModuleValue(text: memoryText())]
            case "wifi": return [ModuleValue(text: wifiText())]
            case "music": return []
            default: return []
            }
        }
    }

    func perform(_ action: String) {
        if action.hasPrefix("workspace:") { aerospace.focus(String(action.dropFirst("workspace:".count))); aerospace.refresh() }
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
        if let ssid = wifiClient.interface()?.ssid(), !ssid.isEmpty { return "🛜 \(ssid)" }
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
