import Darwin
import Foundation

@MainActor
extension BarModel {
    func cpuValues() -> [ModuleValue] {
        [ModuleValue(text: "", spacingAfter: 3, symbolName: "cpu"), ModuleValue(text: String(format: "%.0f%%", lastCPU))]
    }

    func cpuUsage() -> Double {
        var info = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        guard result == KERN_SUCCESS else { return 0 }
        let user = info.cpu_ticks.0, system = info.cpu_ticks.1, idle = info.cpu_ticks.2, nice = info.cpu_ticks.3
        defer { previousTicks = (user, system, idle, nice) }
        guard let old = previousTicks else { return 0 }
        let userDelta = UInt64(user &- old.0)
        let systemDelta = UInt64(system &- old.1)
        let idleDelta = UInt64(idle &- old.2)
        let niceDelta = UInt64(nice &- old.3)
        let totalTicks = userDelta + systemDelta + idleDelta + niceDelta
        guard totalTicks > 0 else { return 0 }
        let activeTicks = userDelta + systemDelta + niceDelta
        return 100 * Double(activeTicks) / Double(totalTicks)
    }
}
