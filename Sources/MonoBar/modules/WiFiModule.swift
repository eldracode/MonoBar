import CoreWLAN
import Foundation
import SystemConfiguration

@MainActor
extension BarModel {
    func wifiText() -> String {
        guard let interface = wifiClient.interface() else { return "—" }
        guard interface.powerOn() else { return "Off" }
        if let ssid = interface.ssid(), !ssid.isEmpty { return ssid }
        guard let store = systemConfigStore else { return "—" }
        var interfaces = wifiClient.interfaceNames() ?? []
        if let defaultInterface = wifiClient.interface()?.interfaceName, !interfaces.contains(defaultInterface) {
            interfaces.insert(defaultInterface, at: 0)
        }
        for name in interfaces {
            let key = "State:/Network/Interface/\(name)/AirPort" as CFString
            guard let state = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                  let ssid = (state["SSID_STR"] as? String) ?? (state["SSID"] as? String),
                  !ssid.isEmpty else { continue }
            return ssid
        }
        return "—"
    }

    func wifiValues() -> [ModuleValue] {
        let rawState = wifiText()
        let isConnectedSSID = rawState != "Off" && rawState != "—"
        let state = config.wifiSSIDMasked && isConnectedSSID ? config.maskedSSIDName : rawState
        let action = "toggle:wifi"
        let symbol = state == "Off" ? "wifi.slash" : "wifi"
        return [
            ModuleValue(text: "", action: action, spacingAfter: 3, symbolName: symbol),
            ModuleValue(text: state, action: action)
        ]
    }

    func toggleWiFi() {
        guard let interface = wifiClient.interface() else { return }
        do {
            try interface.setPower(!interface.powerOn())
            notifyChange()
        } catch {
            NSLog("MonoBar could not toggle Wi-Fi: %@", error.localizedDescription)
        }
    }
}
