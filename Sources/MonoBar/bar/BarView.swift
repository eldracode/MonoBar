import AppKit
import CoreText

final class BarView: NSView {
    private static let fontAwesomeRegistered: Bool = {
        guard let url = Bundle.module.url(forResource: "fa-brands-400", withExtension: "ttf", subdirectory: "Resources") else { return false }
        return CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    private let config: BarConfig
    private let model: BarModel
    private var hitTargets: [(NSRect, String)] = []
    private var scrollTargets: [(NSRect, String)] = []

    init(frame: NSRect, config: BarConfig, model: BarModel) {
        self.config = config; self.model = model
        super.init(frame: frame)
        wantsLayer = true
        model.observe { [weak self] in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        config.background.setFill(); barBackgroundPath().fill()
        config.border.withAlphaComponent(0.65).setStroke()
        let bottomLeft = min(config.radiusBottomLeft, min(bounds.width, bounds.height) / 2)
        let bottomRight = min(config.radiusBottomRight, min(bounds.width, bounds.height) / 2)
        let edge = NSBezierPath()
        edge.move(to: NSPoint(x: bottomLeft, y: 0.5))
        edge.line(to: NSPoint(x: bounds.width - bottomRight, y: 0.5))
        edge.lineWidth = 1
        edge.stroke()
        hitTargets.removeAll(keepingCapacity: true)
        scrollTargets.removeAll(keepingCapacity: true)
        let left = model.values(for: config.left)
        let center = model.values(for: config.center)
        let right = model.values(for: config.right)
        let leftWidth = draw(left, startingAt: config.padding, align: .left)
        let rightWidth = draw(right, startingAt: bounds.width - config.padding, align: .right)
        _ = draw(center, startingAt: bounds.midX, align: .center)
        _ = leftWidth; _ = rightWidth
    }

    private func barBackgroundPath() -> NSBezierPath {
        let width = bounds.width
        let height = bounds.height
        let limit = min(width, height) / 2
        let topLeft = min(config.radiusTopLeft, limit)
        let topRight = min(config.radiusTopRight, limit)
        let bottomRight = min(config.radiusBottomRight, limit)
        let bottomLeft = min(config.radiusBottomLeft, limit)
        let curve: CGFloat = 0.55228475
        let path = NSBezierPath()

        path.move(to: NSPoint(x: bottomLeft, y: 0))
        path.line(to: NSPoint(x: width - bottomRight, y: 0))
        path.curve(
            to: NSPoint(x: width, y: bottomRight),
            controlPoint1: NSPoint(x: width - bottomRight + bottomRight * curve, y: 0),
            controlPoint2: NSPoint(x: width, y: bottomRight - bottomRight * curve)
        )
        path.line(to: NSPoint(x: width, y: height - topRight))
        path.curve(
            to: NSPoint(x: width - topRight, y: height),
            controlPoint1: NSPoint(x: width, y: height - topRight + topRight * curve),
            controlPoint2: NSPoint(x: width - topRight + topRight * curve, y: height)
        )
        path.line(to: NSPoint(x: topLeft, y: height))
        path.curve(
            to: NSPoint(x: 0, y: height - topLeft),
            controlPoint1: NSPoint(x: topLeft - topLeft * curve, y: height),
            controlPoint2: NSPoint(x: 0, y: height - topLeft + topLeft * curve)
        )
        path.line(to: NSPoint(x: 0, y: bottomLeft))
        path.curve(
            to: NSPoint(x: bottomLeft, y: 0),
            controlPoint1: NSPoint(x: 0, y: bottomLeft - bottomLeft * curve),
            controlPoint2: NSPoint(x: bottomLeft - bottomLeft * curve, y: 0)
        )
        path.close()
        return path
    }

    private func draw(_ items: [ModuleValue], startingAt x: CGFloat, align: NSTextAlignment) -> CGFloat {
        let font = NSFont(name: config.fontName, size: config.fontSize) ?? .systemFont(ofSize: config.fontSize, weight: .medium)
        let y = (bounds.height - font.ascender + font.descender) / 2
        let widths = items.map { item -> CGFloat in
            if item.symbolName == "fontawesome-bluetooth", Self.fontAwesomeRegistered,
               let iconFont = NSFont(name: "Font Awesome 6 Brands", size: config.fontSize) {
                return ("\u{f293}" as NSString).size(withAttributes: [.font: iconFont]).width
            }
            if let image = symbolImage(for: item) { return image.size.width }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(for: item)]
            return (item.text as NSString).size(withAttributes: attrs).width
        }
        let spacing = items.dropLast().reduce(CGFloat.zero) { total, item in
            total + (item.spacingAfter ?? config.moduleMargin)
        }
        let total = widths.reduce(0, +) + spacing
        var cursor = align == .left ? x : (align == .right ? x - total : x - total / 2)
        for (index, item) in items.enumerated() {
            let rect = NSRect(x: cursor, y: y, width: widths[index], height: font.ascender - font.descender + font.leading)
            if item.symbolName == "fontawesome-bluetooth", Self.fontAwesomeRegistered,
               let iconFont = NSFont(name: "Font Awesome 6 Brands", size: config.fontSize) {
                ("\u{f293}" as NSString).draw(at: NSPoint(x: cursor, y: y), withAttributes: [.font: iconFont, .foregroundColor: color(for: item)])
            } else if let symbol = symbolImage(for: item) {
                let iconRect = NSRect(
                    x: cursor,
                    y: (bounds.height - symbol.size.height) / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                )
                symbol.draw(in: iconRect)
            } else {
                (item.text as NSString).draw(at: NSPoint(x: cursor, y: y), withAttributes: [.font: font, .foregroundColor: color(for: item)])
            }
            if let action = item.action { hitTargets.append((rect.insetBy(dx: -4, dy: -5), action)) }
            if let action = item.scrollAction { scrollTargets.append((rect.insetBy(dx: -4, dy: -5), action)) }
            cursor += widths[index] + (item.spacingAfter ?? config.moduleMargin)
        }
        return total
    }

    private func symbolImage(for item: ModuleValue) -> NSImage? {
        guard let symbolName = item.symbolName else { return nil }
        let resolvedName = symbolName == "fontawesome-bluetooth" ? "antenna.radiowaves.left.and.right" : symbolName
        let image: NSImage?
        if let variableValue = item.symbolVariableValue {
            image = NSImage(systemSymbolName: resolvedName, variableValue: variableValue, accessibilityDescription: nil)
        } else {
            image = NSImage(systemSymbolName: resolvedName, accessibilityDescription: nil)
        }
        return image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: config.fontSize, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color(for: item)]))
        )
    }

    private func color(for item: ModuleValue) -> NSColor {
        if item.accent { return config.accent }
        return item.muted ? config.foreground.withAlphaComponent(0.5) : config.foreground
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let (_, action) = hitTargets.first(where: { $0.0.contains(point) }) else { return }
        model.perform(action)
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let (_, action) = scrollTargets.first(where: { $0.0.contains(point) }) else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        let magnitude = min(10, max(1, Int((abs(delta) * 2).rounded())))
        model.adjustVolume(action == "volume:input" ? "input" : "output", by: delta > 0 ? magnitude : -magnitude)
    }
}
