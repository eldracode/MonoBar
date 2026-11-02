import AppKit
import Foundation

struct BarConfig {
    var monitor = "main"
    var width = "100%"
    var height: CGFloat = 34
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
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
    var right = ["cpu", "ram", "battery", "wifi", "bluetooth", "clock"]
    var socketPath = (NSHomeDirectory() as NSString).appendingPathComponent(".config/monobar/events.sock")

    static func load() -> BarConfig {
        let home = (NSHomeDirectory() as NSString).appendingPathComponent(".config/monobar/config.toml")
        let legacyHome = (NSHomeDirectory() as NSString).appendingPathComponent(".config/polybar-mac/config.toml")
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let path = xdg.map { ($0 as NSString).appendingPathComponent("monobar/config.toml") } ?? home
        let legacyPath = xdg.map { ($0 as NSString).appendingPathComponent("polybar-mac/config.toml") } ?? legacyHome
        let configPath = FileManager.default.fileExists(atPath: path) ? path : legacyPath
        guard let source = try? String(contentsOfFile: configPath, encoding: .utf8) else { return BarConfig() }
        var result = BarConfig()
        var section = ""
        for raw in source.components(separatedBy: .newlines) {
            var quote: Character?
            var uncommented = ""
            for character in raw {
                if let currentQuote = quote {
                    if character == currentQuote { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "#" {
                    break
                }
                uncommented.append(character)
            }
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
            switch "\(section).\(key)" {
            case "bar.monitor": result.monitor = string()
            case "bar.width": result.width = string()
            case "bar.height": result.height = number(result.height)
            case "bar.offset_x": result.offsetX = number(result.offsetX)
            case "bar.offset_y": result.offsetY = number(result.offsetY)
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
            default: break
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
