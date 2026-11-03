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
        config.background.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 0, yRadius: 0).fill()
        config.border.withAlphaComponent(0.65).setStroke()
        let edge = NSBezierPath(); edge.move(to: NSPoint(x: 0, y: 0.5)); edge.line(to: NSPoint(x: bounds.width, y: 0.5)); edge.lineWidth = 1; edge.stroke()
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

    private func draw(_ items: [ModuleValue], startingAt x: CGFloat, align: NSTextAlignment) -> CGFloat {
        let font = NSFont(name: config.fontName, size: config.fontSize) ?? .systemFont(ofSize: config.fontSize, weight: .medium)
        let y = (bounds.height - font.ascender + font.descender) / 2
        let widths = items.map { item -> CGFloat in
            if item.symbolName == "fontawesome-bluetooth", Self.fontAwesomeRegistered,
               let iconFont = NSFont(name: "Font Awesome 6 Brands", size: config.fontSize) {
                return ("\u{f293}" as NSString).size(withAttributes: [.font: iconFont]).width
            }
            if item.symbolName != nil { return config.fontSize }
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
                ("\u{f293}" as NSString).draw(at: NSPoint(x: cursor, y: y), withAttributes: [.font: iconFont, .foregroundColor: config.accent])
            } else if let symbolName = item.symbolName,
               let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(
                   NSImage.SymbolConfiguration(pointSize: config.fontSize, weight: .regular)
                       .applying(NSImage.SymbolConfiguration(paletteColors: [config.accent]))
               ) {
                symbol.draw(in: NSRect(x: cursor, y: (bounds.height - config.fontSize) / 2, width: config.fontSize, height: config.fontSize))
            } else {
                (item.text as NSString).draw(at: NSPoint(x: cursor, y: y), withAttributes: [.font: font, .foregroundColor: color(for: item)])
            }
            if let action = item.action { hitTargets.append((rect.insetBy(dx: -4, dy: -5), action)) }
            if let action = item.scrollAction { scrollTargets.append((rect.insetBy(dx: -4, dy: -5), action)) }
            cursor += widths[index] + (item.spacingAfter ?? config.moduleMargin)
        }
        return total
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
