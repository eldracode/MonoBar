import AppKit

final class BarView: NSView {
    private let config: BarConfig
    private let model: BarModel
    private var hitTargets: [(NSRect, String)] = []

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
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: item.accent ? config.accent : config.foreground]
            return (item.text as NSString).size(withAttributes: attrs).width
        }
        let total = widths.reduce(0, +) + CGFloat(max(items.count - 1, 0)) * config.moduleMargin
        var cursor = align == .left ? x : (align == .right ? x - total : x - total / 2)
        for (index, item) in items.enumerated() {
            let rect = NSRect(x: cursor, y: y, width: widths[index], height: font.ascender - font.descender + font.leading)
            (item.text as NSString).draw(at: NSPoint(x: cursor, y: y), withAttributes: [.font: font, .foregroundColor: item.accent ? config.accent : config.foreground])
            if let action = item.action { hitTargets.append((rect.insetBy(dx: -4, dy: -5), action)) }
            cursor += widths[index] + config.moduleMargin
        }
        return total
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let (_, action) = hitTargets.first(where: { $0.0.contains(point) }) else { return }
        model.perform(action)
    }
}
