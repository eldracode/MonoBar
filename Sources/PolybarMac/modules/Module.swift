import Foundation

struct ModuleValue {
    var text: String
    var action: String? = nil
    var accent = false
    var muted = false
}

protocol Module {
    var name: String { get }
    func values() -> [ModuleValue]
    func update()
    func handleClick(_ action: String)
}
