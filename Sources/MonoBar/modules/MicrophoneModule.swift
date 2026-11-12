import Foundation

@MainActor
extension BarModel {
    func microphoneValues() -> [ModuleValue] {
        volumeValues(isInput: true)
    }
}
