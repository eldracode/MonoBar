import Foundation

struct Workspace: Identifiable {
    let id: String
    let focused: Bool
    let visible: Bool
    let occupied: Bool
    let screenIndex: Int
}

struct WindowItem: Identifiable {
    let id: String
    let appName: String
    let focused: Bool
}

final class AeroSpace {
    private(set) var workspaces: [Workspace] = []
    private(set) var windows: [WindowItem] = []
    var onChange: (() -> Void)?
    private let executable = "/opt/homebrew/bin/aerospace"

    func refresh() {
        let emptyOutput = Self.run(executable, ["list-workspaces", "--monitor", "all", "--empty", "--format", "%{workspace}"])
        let emptyNames = Set(emptyOutput.split(whereSeparator: \.isNewline).map(String.init))
        let workspaceOutput = Self.run(executable, ["list-workspaces", "--all", "--format", "%{workspace}|%{workspace-is-focused}|%{workspace-is-visible}|%{monitor-appkit-nsscreen-screens-id}"])
        let parsed = workspaceOutput.split(whereSeparator: \.isNewline).compactMap { line -> Workspace? in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4, let screenIndex = Int(fields[3]) else { return nil }
            return Workspace(id: fields[0], focused: fields[1] == "true", visible: fields[2] == "true", occupied: !emptyNames.contains(fields[0]), screenIndex: screenIndex)
        }
        workspaces = parsed.filter { $0.occupied || $0.focused || $0.visible }
        let focusedID = Self.run(executable, ["list-windows", "--focused", "--format", "%{window-id}"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let windowOutput = Self.run(executable, ["list-windows", "--workspace", "focused", "--format", "%{window-id}|%{app-name}"])
        windows = windowOutput.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 2 else { return nil }
            return WindowItem(id: fields[0], appName: fields[1], focused: fields[0] == focusedID)
        }
        onChange?()
    }

    func focus(_ workspace: String) { _ = Self.run(executable, ["workspace", workspace]) }
    func focusWindow(_ windowID: String) { _ = Self.run(executable, ["focus", "--window-id", windowID]) }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = arguments
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return String(decoding: data, as: UTF8.self) } catch { return "" }
    }
}
