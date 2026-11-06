import AppKit

enum BarViewSegment {
    case full
    case leftOfNotch
    case rightOfNotch
}

final class BarPanel: NSPanel {
    let display: NSScreen
    private let floatsOnTop: Bool
    private var hiddenForFullscreen = false

    static func panels(screen: NSScreen, screenIndex: Int, config: BarConfig, model: BarModel) -> [BarPanel] {
        let frame = barFrame(for: screen, config: config)
        guard let notchLeft = screen.auxiliaryTopLeftArea?.maxX,
              let notchRight = screen.auxiliaryTopRightArea?.minX,
              notchRight > notchLeft,
              frame.minX < notchLeft, frame.maxX > notchRight else {
            return [BarPanel(screen: screen, screenIndex: screenIndex, frame: frame, config: config, model: model, segment: .full)]
        }

        let notchInset = max(0, config.offsetSide)
        let leftEnd = max(frame.minX, notchLeft - notchInset)
        let rightStart = min(frame.maxX, notchRight + notchInset)
        var panels: [BarPanel] = []
        if leftEnd > frame.minX {
            let left = NSRect(x: frame.minX, y: frame.minY, width: leftEnd - frame.minX, height: frame.height)
            panels.append(BarPanel(screen: screen, screenIndex: screenIndex, frame: left, config: config, model: model, segment: .leftOfNotch))
        }
        if frame.maxX > rightStart {
            let right = NSRect(x: rightStart, y: frame.minY, width: frame.maxX - rightStart, height: frame.height)
            panels.append(BarPanel(screen: screen, screenIndex: screenIndex, frame: right, config: config, model: model, segment: .rightOfNotch))
        }
        return panels
    }

    private static func barFrame(for screen: NSScreen, config: BarConfig) -> NSRect {
        let screenFrame = screen.frame
        let sideInset = min(config.offsetSide, screenFrame.width / 2)
        let availableWidth = max(0, screenFrame.width - sideInset * 2)
        let width: CGFloat = config.width.hasSuffix("%") ? availableWidth * (CGFloat(Double(config.width.dropLast()) ?? 100) / 100) : (CGFloat(Double(config.width) ?? Double(availableWidth)))
        let topOffset = config.offsetTop ?? config.offsetY
        return NSRect(
            x: screenFrame.minX + sideInset + config.offsetX,
            y: screenFrame.maxY - config.height - topOffset,
            width: min(width, availableWidth),
            height: config.height
        )
    }

    private init(screen: NSScreen, screenIndex: Int, frame: NSRect, config: BarConfig, model: BarModel, segment: BarViewSegment) {
        self.display = screen
        self.floatsOnTop = config.floating
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
        contentView = BarView(frame: NSRect(origin: .zero, size: frame.size), config: config, model: model, screenIndex: screenIndex, segment: segment)
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
