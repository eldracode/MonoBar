import Foundation

@MainActor
extension BarModel {
    func clockValues() -> [ModuleValue] {
        let now = Date()
        let time = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .short)
        let date = DateFormatter.localizedString(from: now, dateStyle: .medium, timeStyle: .none)
        return [
            ModuleValue(text: "", spacingAfter: 3, symbolName: "clock"),
            ModuleValue(text: time),
            ModuleValue(text: "", spacingAfter: 3, symbolName: "calendar"),
            ModuleValue(text: date)
        ]
    }
}
