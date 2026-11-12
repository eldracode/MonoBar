import Darwin
import Foundation

@MainActor
extension BarModel {
    func ramValues() -> [ModuleValue] {
        [ModuleValue(text: "", spacingAfter: 3, symbolName: "memorychip"), ModuleValue(text: memoryText())]
    }

    func memoryText() -> String {
        var stats = vm_statistics64(); var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { p in p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
        guard result == KERN_SUCCESS else { return "—" }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS else { return "—" }
        let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * UInt64(pageSize)
        return String(format: "%.1fG", Double(used) / 1_073_741_824)
    }
}
