import Foundation

@MainActor
extension BarModel {
    func windowTitleValues() -> [ModuleValue] {
        guard !aerospace.windows.isEmpty else { return [] }
        var groups: [(appName: String, windows: [WindowItem])] = []
        var groupIndices: [String: Int] = [:]
        for window in aerospace.windows {
            if let index = groupIndices[window.appName] {
                groups[index].windows.append(window)
            } else {
                groupIndices[window.appName] = groups.count
                groups.append((window.appName, [window]))
            }
        }
        var values = [ModuleValue(text: "│", muted: true)]
        for (groupIndex, group) in groups.enumerated() {
            if groupIndex > 0 { values.append(ModuleValue(text: "•", muted: true)) }
            if group.windows.count == 1, let window = group.windows.first {
                values.append(ModuleValue(text: group.appName, action: "window:\(window.id)", accent: window.focused))
                continue
            }
            values.append(ModuleValue(text: group.appName))
            values.append(ModuleValue(text: "[", muted: true))
            for (index, window) in group.windows.enumerated() {
                if index > 0 { values.append(ModuleValue(text: "•", muted: true)) }
                values.append(ModuleValue(text: "\(index + 1)", action: "window:\(window.id)", accent: window.focused))
            }
            values.append(ModuleValue(text: "]", muted: true))
        }
        return values
    }

    func focusWindow(_ id: String) {
        aerospace.focusWindow(id)
        aerospace.refresh()
    }
}
