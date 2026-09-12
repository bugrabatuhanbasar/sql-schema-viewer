import Foundation
import SchemaKit
import DiagramRenderer

#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// Layer-backed AppKit view that draws a `DiagramScene` using Core Graphics.
/// Wrapped in a scroll view for pan; magnification is set on the enclosing
/// NSScrollView for zoom. Selection sends the selected identifier back via
/// the `onSelect` callback.
final class DiagramCanvasNSView: NSView {
    var scene: DiagramScene = DiagramScene() {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }
    var selectedNode: Identifier? {
        didSet { needsDisplay = true }
    }
    var highlightedNodes: Set<Identifier> = [] {
        didSet { needsDisplay = true }
    }
    var onSelect: (Identifier?) -> Void = { _ in }
    private var indexByName: [Identifier: Int] = [:]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.drawsAsynchronously = true
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override var intrinsicContentSize: NSSize {
        // Padding around the content for aesthetic breathing room.
        let (w, h) = extents
        return NSSize(width: w + 80, height: h + 80)
    }

    private var extents: (Double, Double) {
        var maxX: Double = 0, maxY: Double = 0
        for n in scene.nodes {
            maxX = max(maxX, n.rect.x + n.rect.width)
            maxY = max(maxY, n.rect.y + n.rect.height)
        }
        return (maxX, maxY)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Background
        let bg = NSAppearance.currentDrawing().isDarkMode
            ? CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            : CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        ctx.setFillColor(bg)
        ctx.fill(dirtyRect)

        indexByName.removeAll(keepingCapacity: true)
        for (i, node) in scene.nodes.enumerated() {
            indexByName[Identifier(raw: node.title)] = i
        }

        // Edges first
        ctx.setLineWidth(1.2)
        let edgeColor = NSAppearance.currentDrawing().isDarkMode
            ? CGColor(gray: 0.65, alpha: 0.6)
            : CGColor(gray: 0.35, alpha: 0.6)
        ctx.setStrokeColor(edgeColor)
        for edge in scene.edges {
            let p1 = CGPoint(x: edge.from.x, y: edge.from.y)
            let p2 = CGPoint(x: edge.to.x, y: edge.to.y)
            ctx.beginPath()
            ctx.move(to: p1)
            let midX = (p1.x + p2.x) / 2
            ctx.addCurve(
                to: p2,
                control1: CGPoint(x: midX, y: p1.y),
                control2: CGPoint(x: midX, y: p2.y)
            )
            ctx.strokePath()
        }

        // Nodes
        for node in scene.nodes {
            let rect = CGRect(x: node.rect.x, y: node.rect.y, width: node.rect.width, height: node.rect.height)
            drawNode(ctx: ctx, rect: rect, title: node.title, lines: node.lines,
                     selected: selectedNode?.raw == node.title,
                     highlighted: highlightedNodes.contains(where: { $0.raw == node.title }))
        }
    }

    private func drawNode(ctx: CGContext, rect: CGRect, title: String, lines: [String], selected: Bool, highlighted: Bool) {
        let isDark = NSAppearance.currentDrawing().isDarkMode
        let bodyColor = isDark
            ? CGColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1)
            : CGColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)
        let headerColor = isDark
            ? CGColor(red: 0.22, green: 0.30, blue: 0.42, alpha: 1)
            : CGColor(red: 0.85, green: 0.90, blue: 1.00, alpha: 1)
        let borderColor: CGColor = {
            if selected { return CGColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1) }
            if highlighted { return CGColor(red: 1.00, green: 0.60, blue: 0.20, alpha: 1) }
            return isDark ? CGColor(gray: 0.35, alpha: 1) : CGColor(gray: 0.75, alpha: 1)
        }()
        let textColor = isDark ? NSColor.white : NSColor.black

        let corner: CGFloat = 6
        let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(bodyColor)
        ctx.fillPath()

        let headerRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 28)
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.clip()
        ctx.setFillColor(headerColor)
        ctx.fill(headerRect)
        ctx.restoreGState()

        ctx.addPath(path)
        ctx.setStrokeColor(borderColor)
        ctx.setLineWidth(selected ? 2.0 : 1.0)
        ctx.strokePath()

        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: textColor,
        ]
        let titleString = NSAttributedString(string: title, attributes: titleAttrs)
        let titlePoint = NSPoint(x: headerRect.minX + 10, y: headerRect.minY + 6)
        NSGraphicsContext.current?.saveGraphicsState()
        titleString.draw(at: titlePoint)
        NSGraphicsContext.current?.restoreGraphicsState()

        // Columns
        let lineAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: textColor.withAlphaComponent(0.85),
        ]
        var y = headerRect.maxY + 4
        for line in lines {
            let attr = NSAttributedString(string: line, attributes: lineAttrs)
            attr.draw(at: NSPoint(x: rect.minX + 10, y: y))
            y += 16
            if y > rect.maxY - 8 { break }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for node in scene.nodes.reversed() {
            let rect = CGRect(x: node.rect.x, y: node.rect.y, width: node.rect.width, height: node.rect.height)
            if rect.contains(point) {
                let id = Identifier(raw: node.title)
                selectedNode = id
                onSelect(id)
                return
            }
        }
        selectedNode = nil
        onSelect(nil)
    }
}

/// SwiftUI wrapper hosting the AppKit canvas inside an NSScrollView with
/// magnification.
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
        let scroll = NSScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 3.0
        scroll.magnification = 1.0
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        scroll.backgroundColor = .textBackgroundColor

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
