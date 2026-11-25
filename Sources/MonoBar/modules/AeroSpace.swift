import Foundation

struct Workspace: Identifiable {
    let id: String
    let focused: Bool
    let visible: Bool
    let occupied: Bool
    let screenIndex: Int
    let monitorName: String
}

struct WindowItem: Identifiable {
    let id: String
    let appName: String
    let focused: Bool
}

final class AeroSpace {
    private(set) var workspaces: [Workspace] = []
    private(set) var workspacesByScreen: [Int: [Workspace]] = [:]
    private(set) var windows: [WindowItem] = []
    private(set) var windowsByScreen: [Int: [WindowItem]] = [:]
    var onChange: (() -> Void)?
    private let executable = "/opt/homebrew/bin/aerospace"

    func refresh(notify: Bool = true) {
        refreshWorkspaces(notify: false)
        refreshWindows()
        if notify { onChange?() }
    }

    private func refreshWindows() {
        let focusedID = Self.run(executable, ["list-windows", "--focused", "--format", "%{window-id}"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let windowOutput = Self.run(executable, [
            "list-windows", "--all", "--format",
            "%{window-id}|%{app-name}|%{workspace-is-visible}|%{workspace-is-focused}|%{monitor-appkit-nsscreen-screens-id}"
        ])
        let parsedWindows = windowOutput.split(whereSeparator: \.isNewline).compactMap { line -> (screen: Int, visible: Bool, focusedWorkspace: Bool, window: WindowItem)? in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5, let screen = Int(fields[4]) else { return nil }
            return (
                screen: screen,
                visible: fields[2] == "true",
                focusedWorkspace: fields[3] == "true",
                window: WindowItem(id: fields[0], appName: fields[1], focused: fields[0] == focusedID)
            )
        }
        windows = parsedWindows.filter(\.focusedWorkspace).map(\.window)
        windowsByScreen = Dictionary(grouping: parsedWindows.filter(\.visible), by: \.screen)
            .mapValues { $0.map(\.window) }
    }

    func refreshWorkspaces(notify: Bool = true) {
        let emptyOutput = Self.run(executable, ["list-workspaces", "--monitor", "all", "--empty", "--format", "%{workspace}"])
        let emptyNames = Set(emptyOutput.split(whereSeparator: \.isNewline).map(String.init))
        let workspaceOutput = Self.run(executable, ["list-workspaces", "--all", "--format", "%{workspace}|%{workspace-is-focused}|%{workspace-is-visible}|%{monitor-appkit-nsscreen-screens-id}|%{monitor-name}"])
        let parsed = workspaceOutput.split(whereSeparator: \.isNewline).compactMap { line -> Workspace? in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5, let screenIndex = Int(fields[3]) else { return nil }
            return Workspace(
                id: fields[0],
                focused: fields[1] == "true",
                visible: fields[2] == "true",
                occupied: !emptyNames.contains(fields[0]),
                screenIndex: screenIndex,
                monitorName: fields[4]
            )
        }
        workspaces = parsed.filter { $0.occupied || $0.focused || $0.visible }
        workspacesByScreen = Dictionary(grouping: workspaces, by: \.screenIndex)
        if notify { onChange?() }
    }

    func workspaces(forScreen index: Int?, monitorName: String?) -> [Workspace] {
        guard let index else { return workspaces }
        if let assigned = workspacesByScreen[index] { return assigned }
        if let monitorName {
            return workspaces.filter { $0.monitorName.caseInsensitiveCompare(monitorName) == .orderedSame }
        }
        return []
    }

    func windows(forScreen index: Int?) -> [WindowItem] {
        guard let index else { return windows }
        return windowsByScreen[index] ?? []
    }

    func focus(_ workspace: String) { _ = Self.run(executable, ["workspace", workspace]) }
    func focusWindow(_ windowID: String) { _ = Self.run(executable, ["focus", "--window-id", windowID]) }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = arguments
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return String(decoding: data, as: UTF8.self) } catch { return "" }
    }
}
