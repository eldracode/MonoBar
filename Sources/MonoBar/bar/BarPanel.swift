import AppKit

final class BarPanel: NSPanel {
    let display: NSScreen
    private let floatsOnTop: Bool
    private var hiddenForFullscreen = false

    init(screen: NSScreen, config: BarConfig, model: BarModel) {
        self.display = screen
        self.floatsOnTop = config.floating
        // Anchor to the physical top edge; visibleFrame begins below the menu bar/notch.
        let screenFrame = screen.frame
        let sideInset = min(config.offsetSide, screenFrame.width / 2)
        let availableWidth = max(0, screenFrame.width - sideInset * 2)
        let width: CGFloat = config.width.hasSuffix("%") ? availableWidth * (CGFloat(Double(config.width.dropLast()) ?? 100) / 100) : (CGFloat(Double(config.width) ?? Double(availableWidth)))
        let topOffset = config.offsetTop ?? config.offsetY
        let frame = NSRect(x: screenFrame.minX + sideInset + config.offsetX, y: screenFrame.maxY - config.height - topOffset, width: min(width, availableWidth), height: config.height)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = config.floating ? .statusBar : .normal
        acceptsMouseMovedEvents = true
        // Stay available across normal Spaces, but do not join fullscreen app Spaces.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        contentView = BarView(frame: NSRect(origin: .zero, size: frame.size), config: config, model: model)
        orderFrontRegardless()
    }

    func setMenuBarRevealed(_ revealed: Bool) {
        let desiredLevel: NSWindow.Level = revealed ? .floating : (floatsOnTop ? .statusBar : .normal)
        if level != desiredLevel { level = desiredLevel }
    }

    func setHiddenForFullscreen(_ hidden: Bool) {
        if hidden {
            guard !hiddenForFullscreen else { return }
            hiddenForFullscreen = true
            level = floatsOnTop ? .statusBar : .normal
            orderOut(nil)
        } else if hiddenForFullscreen {
            hiddenForFullscreen = false
            level = floatsOnTop ? .statusBar : .normal
            orderFrontRegardless()
        }
    }

    func showInCurrentSpace() {
        hiddenForFullscreen = false
        orderFrontRegardless()
    }
}
