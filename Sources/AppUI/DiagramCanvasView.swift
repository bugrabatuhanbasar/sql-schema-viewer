import Foundation
import SchemaKit
import DiagramRenderer

#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// Layer-backed AppKit view that draws a `DiagramScene` using Core Graphics.
/// Wrapped in a scroll view for pan; magnification is set on the enclosing
/// NSScrollView for zoom. Nodes are draggable — offsets live in the view
/// and persist as long as the same scene identity is passed in.
final class DiagramCanvasNSView: NSView {
    var scene: DiagramScene = DiagramScene() {
        didSet {
            // Reset offsets when the underlying scene actually changes shape.
            if scene.nodes.count != oldValue.nodes.count {
                nodeOffsets.removeAll()
            }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var selectedNode: Identifier? {
        didSet { needsDisplay = true }
    }
    var highlightedNodes: Set<Identifier> = [] {
        didSet { needsDisplay = true }
    }
    var onSelect: (Identifier?) -> Void = { _ in }

    private var nodeOffsets: [String: CGPoint] = [:]     // node title → user drag delta
    private var draggingNodeTitle: String?
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOffset: CGPoint = .zero
    private let contentPadding: CGFloat = 40

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.drawsAsynchronously = true
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override var intrinsicContentSize: NSSize {
        let (w, h) = extents
        return NSSize(width: w + contentPadding * 2, height: h + contentPadding * 2)
    }

    /// Bounding box of the current scene including user drag offsets.
    private var extents: (Double, Double) {
        var maxX: Double = 0, maxY: Double = 0
        for n in scene.nodes {
            let o = nodeOffsets[n.title] ?? .zero
            maxX = max(maxX, n.rect.x + Double(o.x) + n.rect.width)
            maxY = max(maxY, n.rect.y + Double(o.y) + n.rect.height)
        }
        return (maxX, maxY)
    }

    private func rectFor(_ node: DiagramScene.NodeShape) -> CGRect {
        let o = nodeOffsets[node.title] ?? .zero
        return CGRect(
            x: node.rect.x + Double(o.x) + Double(contentPadding),
            y: node.rect.y + Double(o.y) + Double(contentPadding),
            width: node.rect.width,
            height: node.rect.height
        )
    }

    private func centerFor(title: String) -> CGPoint? {
        guard let node = scene.nodes.first(where: { $0.title == title }) else { return nil }
        let r = rectFor(node)
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// Rect for a node title including live drag offset + padding.
    private func liveRect(forTitle title: String) -> CGRect? {
        guard let node = scene.nodes.first(where: { $0.title == title }) else { return nil }
        return rectFor(node)
    }

    /// Point on the rect border along the line from rect center to `target`.
    private func borderPoint(from rect: CGRect, toward target: (x: CGFloat, y: CGFloat)) -> CGPoint {
        let cx = rect.midX, cy = rect.midY
        let dx = target.x - cx, dy = target.y - cy
        if abs(dx) < 0.0001 && abs(dy) < 0.0001 { return CGPoint(x: cx, y: cy) }
        let hw = rect.width / 2, hh = rect.height / 2
        let sx: CGFloat = abs(dx) > 0.0001 ? hw / abs(dx) : .infinity
        let sy: CGFloat = abs(dy) > 0.0001 ? hh / abs(dy) : .infinity
        let s = min(sx, sy)
        return CGPoint(x: cx + dx * s, y: cy + dy * s)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = NSAppearance.currentDrawing().isDarkMode
        let bg = dark
            ? CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        ctx.setFillColor(bg)
        ctx.fill(dirtyRect)

        // Edges — routed from node border to node border, live-updated
        // through node titles so dragging follows immediately.
        ctx.setLineWidth(1.3)
        let edgeColor = dark
            ? CGColor(gray: 0.70, alpha: 0.85)
            : CGColor(gray: 0.30, alpha: 0.85)
        ctx.setStrokeColor(edgeColor)
        for edge in scene.edges {
            guard let fromRect = liveRect(forTitle: edge.fromTitle),
                  let toRect = liveRect(forTitle: edge.toTitle) else { continue }
            let a = borderPoint(from: fromRect, toward: (toRect.midX, toRect.midY))
            let b = borderPoint(from: toRect, toward: (fromRect.midX, fromRect.midY))
            let midX = (a.x + b.x) / 2
            ctx.beginPath()
            ctx.move(to: a)
            ctx.addCurve(to: b, control1: CGPoint(x: midX, y: a.y), control2: CGPoint(x: midX, y: b.y))
            ctx.strokePath()
            // Cardinality label — 18pt OUTSIDE the node border, along the edge.
            let dx = b.x - a.x, dy = b.y - a.y
            let len = max(1, sqrt(dx * dx + dy * dy))
            let ux = dx / len, uy = dy / len
            let fromLabelPoint = CGPoint(x: a.x + ux * 18, y: a.y + uy * 18)
            let toLabelPoint = CGPoint(x: b.x - ux * 18, y: b.y - uy * 18)
            drawCardinalityLabel(edge.fromCardinality, at: fromLabelPoint, in: ctx, dark: dark)
            drawCardinalityLabel(edge.toCardinality,   at: toLabelPoint,   in: ctx, dark: dark)
        }

        // Nodes
        for node in scene.nodes {
            let rect = rectFor(node)
            drawNode(
                ctx: ctx, rect: rect, title: node.title, lines: node.lines,
                selected: selectedNode?.raw == node.title,
                highlighted: highlightedNodes.contains(where: { $0.raw == node.title }),
                dark: dark
            )
        }
    }

    private func drawCardinalityLabel(_ text: String, at point: CGPoint, in ctx: CGContext, dark: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: dark ? NSColor.white : NSColor(white: 0.15, alpha: 1),
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let size = attr.size()
        let pad: CGFloat = 5
        let bgRect = CGRect(
            x: point.x - size.width / 2 - pad,
            y: point.y - size.height / 2 - 1,
            width: size.width + pad * 2,
            height: size.height + 2
        )
        let bgColor = dark
            ? CGColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 0.95)
            : CGColor(red: 1, green: 1, blue: 1, alpha: 0.97)
        ctx.setFillColor(bgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        ctx.addPath(path); ctx.fillPath()
        ctx.setStrokeColor(dark ? CGColor(gray: 0.55, alpha: 0.7) : CGColor(gray: 0.65, alpha: 0.7))
        ctx.setLineWidth(0.6)
        ctx.addPath(path); ctx.strokePath()
        NSGraphicsContext.current?.saveGraphicsState()
        attr.draw(at: NSPoint(x: bgRect.minX + pad, y: bgRect.minY + 1))
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawNode(ctx: CGContext, rect: CGRect, title: String, lines: [String], selected: Bool, highlighted: Bool, dark: Bool) {
        let bodyColor = dark
            ? CGColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1)
            : CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let headerColor = dark
            ? CGColor(red: 0.22, green: 0.30, blue: 0.42, alpha: 1)
            : CGColor(red: 0.85, green: 0.90, blue: 1, alpha: 1)
        let borderColor: CGColor = {
            if selected { return CGColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1) }
            if highlighted { return CGColor(red: 1.00, green: 0.60, blue: 0.20, alpha: 1) }
            return dark ? CGColor(gray: 0.35, alpha: 1) : CGColor(gray: 0.72, alpha: 1)
        }()
        let textColor = dark ? NSColor.white : NSColor.black

        let corner: CGFloat = 8
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(bodyColor); ctx.fillPath()

        // Drop shadow behind selected/highlighted rows
        if selected || highlighted {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 8, color: borderColor.copy(alpha: 0.4))
            ctx.addPath(path); ctx.setStrokeColor(borderColor); ctx.setLineWidth(1); ctx.strokePath()
            ctx.restoreGState()
        }

        let headerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 30)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.clip()
        ctx.setFillColor(headerColor); ctx.fill(headerRect)
        ctx.restoreGState()

        ctx.addPath(path); ctx.setStrokeColor(borderColor); ctx.setLineWidth(selected ? 2 : 1); ctx.strokePath()

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: textColor,
        ]
        NSAttributedString(string: title, attributes: titleAttrs)
            .draw(at: NSPoint(x: headerRect.minX + 10, y: headerRect.minY + 7))

        // Columns
        let lineAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: textColor.withAlphaComponent(0.85),
        ]
        var y = headerRect.maxY + 4
        for line in lines {
            NSAttributedString(string: line, attributes: lineAttrs)
                .draw(at: NSPoint(x: rect.minX + 10, y: y))
            y += 16
            if y > rect.maxY - 8 { break }
        }
    }

    // MARK: interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for node in scene.nodes.reversed() {
            let r = rectFor(node)
            if r.contains(point) {
                selectedNode = Identifier(raw: node.title)
                onSelect(selectedNode)
                draggingNodeTitle = node.title
                dragStartMouse = point
                dragStartOffset = nodeOffsets[node.title] ?? .zero
                NSCursor.closedHand.push()
                return
            }
        }
        selectedNode = nil
        onSelect(nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let title = draggingNodeTitle else { return }
        let p = convert(event.locationInWindow, from: nil)
        let delta = CGPoint(x: p.x - dragStartMouse.x, y: p.y - dragStartMouse.y)
        nodeOffsets[title] = CGPoint(x: dragStartOffset.x + delta.x, y: dragStartOffset.y + delta.y)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if draggingNodeTitle != nil {
            NSCursor.pop()
            draggingNodeTitle = nil
        }
        super.mouseUp(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for node in scene.nodes {
            addCursorRect(rectFor(node), cursor: .openHand)
        }
    }
}

/// SwiftUI wrapper hosting the AppKit canvas inside an NSScrollView with
/// magnification. A flipped, layer-backed wrapper view keeps the diagram
/// centered when it's smaller than the visible area, so the content never
/// pins to the top-left edge on wide monitors.
public struct DiagramCanvasView: NSViewRepresentable {
    public var scene: DiagramScene
    public var selection: Identifier?
    public var highlights: Set<Identifier>
    public var onSelect: (Identifier?) -> Void

    public init(scene: DiagramScene, selection: Identifier?, highlights: Set<Identifier>, onSelect: @escaping (Identifier?) -> Void) {
        self.scene = scene
        self.selection = selection
        self.highlights = highlights
        self.onSelect = onSelect
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = CenteringScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 3.0
        scroll.magnification = 1.0
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.backgroundColor = .textBackgroundColor
        scroll.drawsBackground = true

        let canvas = DiagramCanvasNSView(frame: .zero)
        canvas.scene = scene
        canvas.selectedNode = selection
        canvas.highlightedNodes = highlights
        canvas.onSelect = onSelect
        scroll.documentView = canvas
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let canvas = scroll.documentView as? DiagramCanvasNSView else { return }
        canvas.scene = scene
        canvas.selectedNode = selection
        canvas.highlightedNodes = highlights
        canvas.onSelect = onSelect
        canvas.frame.size = canvas.intrinsicContentSize
        (scroll as? CenteringScrollView)?.recenterIfNeeded()
    }
}

/// NSScrollView subclass that keeps the document view centered inside the
/// clip view when the content is smaller than the visible area, matching
/// what most macOS diagram viewers do (Preview, Xcode's storyboard editor).
final class CenteringScrollView: NSScrollView {
    override func tile() {
        super.tile()
        recenterIfNeeded()
    }
    func recenterIfNeeded() {
        guard let doc = documentView else { return }
        let clipSize = contentView.bounds.size
        let docSize = doc.frame.size
        var origin = doc.frame.origin
        if docSize.width < clipSize.width {
            origin.x = (clipSize.width - docSize.width) / 2
        } else {
            origin.x = 0
        }
        if docSize.height < clipSize.height {
            origin.y = (clipSize.height - docSize.height) / 2
        } else {
            origin.y = 0
        }
        doc.frame = CGRect(origin: origin, size: docSize)
    }
}

extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    static func currentDrawing() -> NSAppearance {
        NSAppearance.current ?? NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!
    }
}
#endif
