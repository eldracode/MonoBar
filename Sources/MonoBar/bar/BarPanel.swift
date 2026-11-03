import AppKit

final class BarPanel: NSPanel {
    let display: NSScreen
    private var hiddenForFullscreen = false

    init(screen: NSScreen, config: BarConfig, model: BarModel) {
        self.display = screen
        // Anchor to the physical top edge; visibleFrame begins below the menu bar/notch.
        let screenFrame = screen.frame
        let width: CGFloat = config.width.hasSuffix("%") ? screenFrame.width * (CGFloat(Double(config.width.dropLast()) ?? 100) / 100) : (CGFloat(Double(config.width) ?? Double(screenFrame.width)))
        let frame = NSRect(x: screenFrame.minX + config.offsetX, y: screenFrame.maxY - config.height - config.offsetY, width: min(width, screenFrame.width), height: config.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        acceptsMouseMovedEvents = true
        // Stay available across normal Spaces, but do not join fullscreen app Spaces.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        contentView = BarView(frame: NSRect(origin: .zero, size: frame.size), config: config, model: model)
        orderFrontRegardless()
    }

    func setMenuBarRevealed(_ revealed: Bool) {
        let desiredLevel: NSWindow.Level = revealed ? .floating : .statusBar
        if level != desiredLevel { level = desiredLevel }
    }

    func setHiddenForFullscreen(_ hidden: Bool) {
        if hidden {
            guard !hiddenForFullscreen else { return }
            hiddenForFullscreen = true
            level = .statusBar
            orderOut(nil)
        } else if hiddenForFullscreen {
            hiddenForFullscreen = false
            orderFrontRegardless()
        }
    }

    func showInCurrentSpace() {
        hiddenForFullscreen = false
        orderFrontRegardless()
    }
}
