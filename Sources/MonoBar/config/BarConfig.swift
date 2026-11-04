import AppKit
import Foundation

struct MonitorConfig {
    var screen: String?
    var width: String?
    var height: CGFloat?
    var offsetX: CGFloat?
    var offsetY: CGFloat?
    var offsetTop: CGFloat?
    var offsetSide: CGFloat?
    var floating: Bool?
    var radiusTopLeft: CGFloat?
    var radiusTopRight: CGFloat?
    var radiusBottomRight: CGFloat?
    var radiusBottomLeft: CGFloat?
    var padding: CGFloat?
    var moduleMargin: CGFloat?
    var left: [String]?
    var center: [String]?
    var right: [String]?
}

struct BarConfig {
    var monitor = "main"
    var width = "100%"
    var height: CGFloat = 34
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var offsetTop: CGFloat?
    var offsetSide: CGFloat = 0
    var floating = true
    var radiusTopLeft: CGFloat = 0
    var radiusTopRight: CGFloat = 0
    var radiusBottomRight: CGFloat = 0
    var radiusBottomLeft: CGFloat = 0
    var padding: CGFloat = 14
    var moduleMargin: CGFloat = 10
    var background = NSColor(hex: "171A21E8")
    var foreground = NSColor(hex: "E7EAF0")
    var border = NSColor(hex: "343A46")
    var accent = NSColor(hex: "8AB4F8")
    var fontName = "SF Pro Text"
    var fallbackFontName = "Apple Symbols"
    var fontSize: CGFloat = 13
    var left = ["workspaces", "title"]
    var center = ["music"]
    var right = ["cpu", "ram", "battery", "volume", "mic", "wifi", "bluetooth", "weather", "clock"]
    var socketPath = (NSHomeDirectory() as NSString).appendingPathComponent(".config/monobar/events.sock")
    var weatherProvider = "openweather"
    var weatherAPIKey = ""
    var weatherUnits = "metric"
    var weatherLatitude: Double?
    var weatherLongitude: Double?
    var weatherRefreshMinutes: Double = 15
    var wifiSSIDMasked = false
    var maskedSSIDName = "<redacted>"
    var monitorConfigs: [MonitorConfig] = []

    func config(for screen: NSScreen) -> BarConfig {
        guard let override = monitorConfigs.first(where: { profile in
            guard let selector = profile.screen else { return false }
            if selector.caseInsensitiveCompare("main") == .orderedSame {
                return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID()
            }
            if selector.lowercased().hasPrefix("id:"),
               let id = UInt32(selector.dropFirst(3)) {
                return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }
            return screen.localizedName.localizedCaseInsensitiveCompare(selector) == .orderedSame
        }) else { return self }

        var resolved = self
        if let value = override.width { resolved.width = value }
        if let value = override.height { resolved.height = value }
        if let value = override.offsetX { resolved.offsetX = value }
        if let value = override.offsetY { resolved.offsetY = value }
        if let value = override.offsetTop { resolved.offsetTop = value }
        if let value = override.offsetSide { resolved.offsetSide = max(0, value) }
        if let value = override.floating { resolved.floating = value }
        if let value = override.radiusTopLeft { resolved.radiusTopLeft = max(0, value) }
        if let value = override.radiusTopRight { resolved.radiusTopRight = max(0, value) }
        if let value = override.radiusBottomRight { resolved.radiusBottomRight = max(0, value) }
        if let value = override.radiusBottomLeft { resolved.radiusBottomLeft = max(0, value) }
        if let value = override.padding { resolved.padding = value }
        if let value = override.moduleMargin { resolved.moduleMargin = value }
        if let value = override.left { resolved.left = value }
        if let value = override.center { resolved.center = value }
        if let value = override.right { resolved.right = value }
        return resolved
    }

    static func load() -> BarConfig {
        let home = (NSHomeDirectory() as NSString).appendingPathComponent(".config/monobar/config.toml")
        let legacyHome = (NSHomeDirectory() as NSString).appendingPathComponent(".config/polybar-mac/config.toml")
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let path = xdg.map { ($0 as NSString).appendingPathComponent("monobar/config.toml") } ?? home
        let legacyPath = xdg.map { ($0 as NSString).appendingPathComponent("polybar-mac/config.toml") } ?? legacyHome
        let configPath = FileManager.default.fileExists(atPath: path) ? path : legacyPath
        guard let source = try? String(contentsOfFile: configPath, encoding: .utf8) else { return BarConfig() }
        var result = BarConfig()
        var monitorConfigs: [String: MonitorConfig] = [:]
        var section = ""
        for raw in source.components(separatedBy: .newlines) {
            let uncommented = stripComment(from: raw)
            let line = uncommented.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") { section = String(line.dropFirst().dropLast()); continue }
            let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespaces)
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            func number(_ fallback: CGFloat) -> CGFloat { CGFloat(Double(value) ?? Double(fallback)) }
            func string() -> String { value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            func strings() -> [String] {
                value.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'"))) }.filter { !$0.isEmpty }
            }
            if section.hasPrefix("monitors.") {
                let profileName = String(section.dropFirst("monitors.".count))
                var profile = monitorConfigs[profileName] ?? MonitorConfig()
                switch key {
                case "screen": profile.screen = string()
                case "width": profile.width = string()
                case "height": profile.height = number(0)
                case "offset_x": profile.offsetX = number(0)
                case "offset_y": profile.offsetY = number(0)
                case "offset_top": profile.offsetTop = number(0)
                case "offset_side": profile.offsetSide = number(0)
                case "float": profile.floating = value.lowercased() == "true"
                case "radius_top_left": profile.radiusTopLeft = number(0)
                case "radius_top_right": profile.radiusTopRight = number(0)
                case "radius_bottom_right": profile.radiusBottomRight = number(0)
                case "radius_bottom_left": profile.radiusBottomLeft = number(0)
                case "padding": profile.padding = number(0)
                case "module_margin": profile.moduleMargin = number(0)
                case "modules-left": profile.left = strings()
                case "modules-center": profile.center = strings()
                case "modules-right": profile.right = strings()
                default: break
                }
                monitorConfigs[profileName] = profile
                continue
            }
            switch "\(section).\(key)" {
            case "bar.monitor": result.monitor = string()
            case "bar.width": result.width = string()
            case "bar.height": result.height = number(result.height)
            case "bar.offset_x": result.offsetX = number(result.offsetX)
            case "bar.offset_y": result.offsetY = number(result.offsetY)
            case "bar.offset_top": result.offsetTop = number(0)
            case "bar.offset_side": result.offsetSide = max(0, number(0))
            case "bar.float": result.floating = value.lowercased() == "true"
            case "bar.radius_top_left": result.radiusTopLeft = max(0, number(result.radiusTopLeft))
            case "bar.radius_top_right": result.radiusTopRight = max(0, number(result.radiusTopRight))
            case "bar.radius_bottom_right": result.radiusBottomRight = max(0, number(result.radiusBottomRight))
            case "bar.radius_bottom_left": result.radiusBottomLeft = max(0, number(result.radiusBottomLeft))
            case "bar.padding": result.padding = number(result.padding)
            case "bar.module_margin": result.moduleMargin = number(result.moduleMargin)
            case "bar.socket":
                let socket = string()
                result.socketPath = socket.hasPrefix("~/") ? (NSHomeDirectory() as NSString).appendingPathComponent(String(socket.dropFirst(2))) : socket
            case "colors.background": result.background = NSColor(hex: string())
            case "colors.foreground": result.foreground = NSColor(hex: string())
            case "colors.border": result.border = NSColor(hex: string())
            case "colors.accent": result.accent = NSColor(hex: string())
            case "fonts.primary": result.fontName = string()
            case "fonts.fallback": result.fallbackFontName = string()
            case "fonts.size": result.fontSize = number(result.fontSize)
            case "layout.modules-left": result.left = strings()
            case "layout.modules-center": result.center = strings()
            case "layout.modules-right": result.right = strings()
            case "weather.provider": result.weatherProvider = string().lowercased()
            case "weather.api_key": result.weatherAPIKey = string()
            case "weather.units":
                let units = string().lowercased()
                if ["metric", "imperial", "standard"].contains(units) { result.weatherUnits = units }
            case "weather.latitude": result.weatherLatitude = Double(value)
            case "weather.longitude": result.weatherLongitude = Double(value)
            case "weather.refresh_minutes":
                if let minutes = Double(value), minutes >= 1 { result.weatherRefreshMinutes = minutes }
            case "wifi.wifi_ssid_masked": result.wifiSSIDMasked = value.lowercased() == "true"
            case "wifi.masked_ssid_name": result.maskedSSIDName = string().isEmpty ? "<redacted>" : string()
            default: break
            }
        }
        result.monitorConfigs = monitorConfigs.keys.sorted().compactMap { monitorConfigs[$0] }
        return result
    }

    private static func stripComment(from line: String) -> String {
        var quote: Character?
        var escaped = false
        var result = ""
        for character in line {
            if let currentQuote = quote {
                if currentQuote == "\"" && escaped {
                    escaped = false
                } else if currentQuote == "\"" && character == "\\" {
                    escaped = true
                } else if character == currentQuote {
                    quote = nil
                }
                result.append(character)
            } else if character == "\"" || character == "'" {
                quote = character
                result.append(character)
            } else if character == "#" {
                break
            } else {
                result.append(character)
            }
        }
        return result
    }
}

extension NSColor {
    convenience init(hex: String) {
        let raw = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(raw, radix: 16) ?? 0x171A21
        if raw.count == 8 {
            self.init(red: CGFloat((value >> 24) & 255) / 255, green: CGFloat((value >> 16) & 255) / 255, blue: CGFloat((value >> 8) & 255) / 255, alpha: CGFloat(value & 255) / 255)
        } else {
            self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
        }
    }
}
