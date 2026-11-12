import Foundation
import IOKit.ps

@MainActor
extension BarModel {
    func batteryValues() -> [ModuleValue] {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef], let source = list.first, let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
            return [ModuleValue(text: "", spacingAfter: 3, symbolName: "battery.0percent"), ModuleValue(text: "—")]
        }
        let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let onACPower = (description[kIOPSPowerSourceStateKey] as? String) == "AC Power"
        let level = min(100, max(0, current))
        let symbol: String
        switch level {
        case ..<13: symbol = "battery.0percent"
        case ..<38: symbol = "battery.25percent"
        case ..<63: symbol = "battery.50percent"
        case ..<88: symbol = "battery.75percent"
        default: symbol = "battery.100percent"
        }
        var values = [ModuleValue(text: "", spacingAfter: 3, symbolName: symbol, warning: level < 20)]
        if charging || onACPower {
            values.append(ModuleValue(text: "", accent: true, spacingAfter: 3, symbolName: "bolt.fill"))
        }
        values.append(ModuleValue(text: "\(level)%"))
        return values
    }
}
