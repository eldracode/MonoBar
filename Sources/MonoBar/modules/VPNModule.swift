import Foundation

enum VPNConnectionState {
    case disconnected
    case connecting
    case connected
    case disconnecting

    var label: String {
        switch self {
        case .disconnected: "Off"
        case .connecting: "Connecting"
        case .connected: "On"
        case .disconnecting: "Disconnecting"
        }
    }

    var symbol: String {
        switch self {
        case .disconnected: "lock.shield"
        case .connecting, .disconnecting: "hourglass"
        case .connected: "lock.shield.fill"
        }
    }
}

@MainActor
extension BarModel {
    func vpnValues() -> [ModuleValue] {
        let isConfigured = !config.vpnProfileID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let label = !isConfigured ? "Set profile" : (vpnProfileExists == false ? "Profile missing" : vpnState.label)
        let action = isConfigured && vpnProfileExists != false ? "toggle:vpn" : nil
        return [
            ModuleValue(text: "", action: action, accent: vpnState == .connected, spacingAfter: 3, symbolName: vpnState.symbol),
            ModuleValue(text: label, action: action, accent: vpnState == .connected)
        ]
    }

    func toggleVPN() {
        let profileID = config.vpnProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profileID.isEmpty, vpnProfileExists != false,
              vpnState != .connecting, vpnState != .disconnecting else { return }
        let shouldConnect = vpnState != .connected
        vpnState = shouldConnect ? .connecting : .disconnecting
        notifyChange()

        let path = "/Applications/OpenVPN Connect/OpenVPN Connect.app/contents/MacOS/OpenVPN Connect"
        let arguments = shouldConnect ? ["--connect-shortcut=\(profileID)"] : ["--disconnect-shortcut"]
        Task.detached(priority: .utility) {
            let succeeded = Self.runVPNCommand(path: path, arguments: arguments)
            await MainActor.run {
                self.vpnState = succeeded
                    ? (shouldConnect ? .connected : .disconnected)
                    : (shouldConnect ? .disconnected : .connected)
                self.refreshVPNStatus(force: true)
                self.notifyChange()
            }
        }
    }

    func refreshVPNStatus(force: Bool = false) {
        guard !config.vpnProfileID.isEmpty, !vpnStatusRefreshInFlight,
              force || Date().timeIntervalSince(vpnLastStatusCheck) >= 5 else { return }
        vpnStatusRefreshInFlight = true
        let profileID = config.vpnProfileID
        let knownProfileName = vpnProfileName
        let path = "/Applications/OpenVPN Connect/OpenVPN Connect.app/contents/MacOS/OpenVPN Connect"
        Task.detached(priority: .utility) {
            let profileResult: (String?, Bool)
            if let knownProfileName {
                profileResult = (knownProfileName, true)
            } else {
                profileResult = Self.lookupVPNProfile(path: path, profileID: profileID)
            }
            let state = profileResult.0.flatMap { Self.readVPNState(profileName: $0) }
            await MainActor.run {
                self.vpnStatusRefreshInFlight = false
                self.vpnLastStatusCheck = Date()
                self.vpnProfileExists = profileResult.1
                if let name = profileResult.0 { self.vpnProfileName = name }
                if let state { self.vpnState = state }
                self.notifyChange()
            }
        }
    }

    nonisolated private static func lookupVPNProfile(path: String, profileID: String) -> (String?, Bool) {
        guard let output = runVPNCommandOutput(path: path, arguments: ["--list-profiles"]),
              let data = output.data(using: .utf8),
              let profiles = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return (nil, true)
        }
        guard let profile = profiles.first(where: { ($0["id"] as? String) == profileID }) else {
            return (nil, false)
        }
        return (profile["name"] as? String, true)
    }

    nonisolated private static func readVPNState(profileName: String) -> VPNConnectionState? {
        guard let output = runVPNCommandOutput(path: "/usr/sbin/scutil", arguments: ["--nc", "list"]) else { return nil }
        for line in output.components(separatedBy: .newlines)
            where line.localizedCaseInsensitiveContains(profileName) {
            if line.contains("(Connected)") { return .connected }
            if line.contains("(Connecting)") { return .connecting }
            if line.contains("(Disconnecting)") { return .disconnecting }
            if line.contains("(Disconnected)") || line.contains("(Invalid)") { return .disconnected }
        }
        return nil
    }

    nonisolated private static func runVPNCommand(path: String, arguments: [String]) -> Bool {
        runVPNCommandOutput(path: path, arguments: arguments) != nil
    }

    nonisolated private static func runVPNCommandOutput(path: String, arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
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
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self)
        } catch {
            return nil
        }
    }
}
