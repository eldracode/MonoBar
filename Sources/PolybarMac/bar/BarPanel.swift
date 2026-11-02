import AppKit

final class BarPanel: NSPanel {
    init(screen: NSScreen, config: BarConfig, model: BarModel) {
        // Use the usable screen area so the top edge clears the menu bar and notch.
        let visible = screen.visibleFrame
        let width: CGFloat = config.width.hasSuffix("%") ? visible.width * (CGFloat(Double(config.width.dropLast()) ?? 100) / 100) : (CGFloat(Double(config.width) ?? Double(visible.width)))
        let frame = NSRect(x: visible.minX + config.offsetX, y: visible.maxY - config.height - config.offsetY, width: min(width, visible.width), height: config.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        contentView = BarView(frame: NSRect(origin: .zero, size: frame.size), config: config, model: model)
        orderFrontRegardless()
    }
}
