import Foundation

struct Workspace: Identifiable {
    let id: String
    let focused: Bool
    let visible: Bool
    let occupied: Bool
}

final class AeroSpace {
    private(set) var workspaces: [Workspace] = []
    private(set) var title = ""
    var onChange: (() -> Void)?
    private let executable = "/opt/homebrew/bin/aerospace"

    func refresh() {
        let emptyOutput = Self.run(executable, ["list-workspaces", "--all", "--empty", "--format", "%{workspace}"])
        let emptyNames = Set(emptyOutput.split(whereSeparator: \.isNewline).map(String.init))
        let workspaceOutput = Self.run(executable, ["list-workspaces", "--all", "--format", "%{workspace}|%{workspace-is-focused}|%{workspace-is-visible}"])
        let parsed = workspaceOutput.split(whereSeparator: \.isNewline).compactMap { line -> Workspace? in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { return nil }
            return Workspace(id: fields[0], focused: fields[1] == "true", visible: fields[2] == "true", occupied: !emptyNames.contains(fields[0]))
        }
        workspaces = parsed
        title = Self.run(executable, ["list-windows", "--focused", "--format", "%{app-name} — %{window-title}"]).trimmingCharacters(in: .whitespacesAndNewlines)
        onChange?()
    }

    func focus(_ workspace: String) { _ = Self.run(executable, ["workspace", workspace]) }

    private static func run(_ path: String, _ arguments: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = arguments
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do { try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return String(decoding: data, as: UTF8.self) } catch { return "" }
    }
}
