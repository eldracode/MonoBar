import Foundation
import IOBluetooth

@MainActor
extension BarModel {
    func bluetoothValues() -> [ModuleValue] {
        guard IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON else {
            return [ModuleValue(text: "", action: "toggle:bluetooth", spacingAfter: 3, symbolName: "fontawesome-bluetooth"), ModuleValue(text: "Off", action: "toggle:bluetooth")]
        }
        let connected = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
            .first(where: { $0.isConnected() })
        let state = connected?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "On"
        return [ModuleValue(text: "", action: "toggle:bluetooth", spacingAfter: 3, symbolName: "fontawesome-bluetooth"), ModuleValue(text: state, action: "toggle:bluetooth")]
    }

    func toggleBluetooth() {
        let path = ["/opt/homebrew/bin/blueutil", "/usr/local/bin/blueutil"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        guard let path else { return }
        let state = runBlueutil(path: path, arguments: ["--power"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard state == "0" || state == "1" else { return }
        _ = runBlueutil(path: path, arguments: ["--power", state == "1" ? "0" : "1"])
        notifyChange()
    }

    func runBlueutil(path: String, arguments: [String]) -> String {
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
}
