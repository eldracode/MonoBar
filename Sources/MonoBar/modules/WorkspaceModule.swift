import Foundation

@MainActor
extension BarModel {
    func workspaceValues(screenIndex: Int?) -> [ModuleValue] {
        aerospace.workspaces
            .filter { screenIndex == nil || $0.screenIndex == screenIndex }
            .map { workspace in
                let marker = workspace.focused ? "●" : (workspace.visible ? "◉" : (workspace.occupied ? "•" : "○"))
                return ModuleValue(
                    text: "\(marker) \(workspace.id)",
                    action: "workspace:\(workspace.id)",
                    accent: workspace.focused || workspace.visible
                )
            }
    }

    func focusWorkspace(_ id: String) {
        aerospace.focus(id)
        aerospace.refresh()
    }
}
