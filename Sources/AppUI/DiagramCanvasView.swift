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
            // SwiftUI re-runs updateNSView on every state change and re-
            // assigns the (same) scene value, so we can only invalidate
            // node offsets / the edge highlight when the scene actually
            // changed. Compare by node titles + edge count — cheap and
            // catches every case that would invalidate an edge index.
            let shapeChanged =
                scene.nodes.count != oldValue.nodes.count ||
                scene.edges.count != oldValue.edges.count ||
                zip(scene.nodes, oldValue.nodes).contains(where: { $0.title != $1.title })
            if shapeChanged {
                nodeOffsets.removeAll()
                selectedEdgeIndex = nil
            }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var selectedNodes: Set<Identifier> = [] {
        didSet {
            // Any change to the node selection clears the visual edge
            // highlight — otherwise the accent line lingers after the
            // user picks something else.
            if selectedNodes != oldValue { selectedEdgeIndex = nil }
            needsDisplay = true
        }
    }
    var highlightedNodes: Set<Identifier> = [] {
        didSet { needsDisplay = true }
    }
    /// Called whenever the selection changes (click, marquee, keyboard).
    var onSelectionChanged: (Set<Identifier>) -> Void = { _ in }

    private var nodeOffsets: [String: CGPoint] = [:]     // node title → user drag delta
    private var draggingTitles: Set<String> = []
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOffsets: [String: CGPoint] = [:]
    private var marqueeAnchor: NSPoint?
    private var marqueeCurrent: NSPoint?
    /// Index into `scene.edges` for the edge currently highlighted after
    /// an edge-click. Reset whenever the scene changes shape or the node
    /// selection changes, so the highlight tracks the most recent action.
    private var selectedEdgeIndex: Int? {
        didSet { needsDisplay = true }
    }
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

    /// Live orthogonal waypoints for the given edge.
    ///
    /// The router bakes waypoints in the padding-free layout coordinate
    /// space at scene-build time. Two things happen here to display them:
    ///
    /// 1. A single `contentPadding` translation is applied to every point
    ///    — same shift the node rects get in `rectFor(_:)`. Previously
    ///    this padding was added *twice* (once via the fromRect/toRect
    ///    midpoint delta, once explicitly), so orthogonal edges started
    ///    life 40 pt away from the tables they were supposed to touch.
    ///    That was the "not glued to boxes" bug.
    ///
    /// 2. Any per-node drag delta from `nodeOffsets` is added to the
    ///    corresponding half of the polyline. The first half of the
    ///    polyline (index < count/2) follows the source; the second half
    ///    follows the target. Middle vertices in a 4-point Z-shape belong
    ///    to whichever half is closer to them, so an edge stays glued to
    ///    both endpoints when either is being dragged.
    private func liveOrthogonalPath(for edge: DiagramScene.EdgeShape) -> [CGPoint]? {
        guard !edge.waypoints.isEmpty else { return nil }
        let fromDrag = nodeOffsets[edge.fromTitle] ?? .zero
        let toDrag   = nodeOffsets[edge.toTitle]   ?? .zero
        let n = edge.waypoints.count
        let mid = n / 2
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for (i, wp) in edge.waypoints.enumerated() {
            let source = i < mid
            let drag = source ? fromDrag : toDrag
            pts.append(CGPoint(
                x: CGFloat(wp.x) + drag.x + contentPadding,
                y: CGFloat(wp.y) + drag.y + contentPadding
            ))
        }
        return pts
    }

    /// Compute the four control points for an edge's cubic bezier given the
    /// current live rects and the same detour logic as drawing. Returns
    /// nil if either endpoint's rect can't be found.
    private struct BezierGeom { var a, c1, c2, b: CGPoint }
    private func bezier(for edge: DiagramScene.EdgeShape, diagramBounds: (Double, Double)) -> BezierGeom? {
        guard let fromRect = liveRect(forTitle: edge.fromTitle),
              let toRect = liveRect(forTitle: edge.toTitle) else { return nil }
        let a = borderPoint(from: fromRect, toward: (toRect.midX, toRect.midY))
        let b = borderPoint(from: toRect, toward: (fromRect.midX, fromRect.midY))
        let (bx0, bx1) = diagramBounds
        let c1: CGPoint, c2: CGPoint
        if edge.isLongSpan {
            let bothLeftHalf = (a.x + b.x) / 2 < (bx0 + bx1) / 2
            let detourX: CGFloat = bothLeftHalf ? CGFloat(bx0) - 60 : CGFloat(bx1) + 60
            c1 = CGPoint(x: detourX, y: a.y)
            c2 = CGPoint(x: detourX, y: b.y)
        } else {
            let midX = (a.x + b.x) / 2
            c1 = CGPoint(x: midX, y: a.y)
            c2 = CGPoint(x: midX, y: b.y)
        }
        return BezierGeom(a: a, c1: c1, c2: c2, b: b)
    }

    private static func evalBezier(_ g: BezierGeom, at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = u*u*u*g.a.x + 3*u*u*t*g.c1.x + 3*u*t*t*g.c2.x + t*t*t*g.b.x
        let y = u*u*u*g.a.y + 3*u*u*t*g.c1.y + 3*u*t*t*g.c2.y + t*t*t*g.b.y
        return CGPoint(x: x, y: y)
    }

    /// Diagram content bounds (min x, max x) used by the detour router.
    private func currentDiagramBounds() -> (Double, Double) {
        let allRects = scene.nodes.compactMap { liveRect(forTitle: $0.title) }
        let bx0 = allRects.map(\.minX).min() ?? 0
        let bx1 = allRects.map(\.maxX).max() ?? 0
        return (Double(bx0), Double(bx1))
    }

    /// Nearest edge under a point, or nil if none is within `tolerance` px.
    /// Handles both routing modes: for orthogonal edges we sample every
    /// polyline segment; for curved edges we sample the bezier.
    private func edgeAt(_ point: NSPoint, tolerance: CGFloat = 7) -> Int? {
        let bounds = currentDiagramBounds()
        var best: (index: Int, dist: CGFloat)? = nil
        for (idx, edge) in scene.edges.enumerated() {
            var minD: CGFloat = .infinity
            if let poly = liveOrthogonalPath(for: edge) {
                for i in 0..<(poly.count - 1) {
                    let d = distanceFromPoint(point, toSegmentFrom: poly[i], to: poly[i + 1])
                    if d < minD { minD = d }
                }
            } else if let g = bezier(for: edge, diagramBounds: bounds) {
                let steps = 32
                for k in 0...steps {
                    let t = CGFloat(k) / CGFloat(steps)
                    let p = Self.evalBezier(g, at: t)
                    let dx = point.x - p.x, dy = point.y - p.y
                    let d = sqrt(dx * dx + dy * dy)
                    if d < minD { minD = d }
                }
            }
            if minD <= tolerance {
                if best == nil || minD < best!.dist { best = (idx, minD) }
            }
        }
        return best?.index
    }

    private func strokeSharpPolyline(_ pts: [CGPoint], in ctx: CGContext) {
        guard pts.count >= 2 else { return }
        ctx.beginPath()
        ctx.move(to: pts[0])
        for i in 1..<pts.count { ctx.addLine(to: pts[i]) }
        ctx.strokePath()
    }

    private func strokeRoundedPolyline(_ pts: [CGPoint], radius: CGFloat, in ctx: CGContext) {
        guard pts.count >= 2 else { return }
        ctx.beginPath()
        ctx.move(to: pts[0])
        for i in 1..<(pts.count - 1) {
            let prev = pts[i - 1], curr = pts[i], next = pts[i + 1]
            let dxIn  = curr.x - prev.x, dyIn  = curr.y - prev.y
            let dxOut = next.x - curr.x, dyOut = next.y - curr.y
            let lenIn  = max(0.0001, hypot(dxIn, dyIn))
            let lenOut = max(0.0001, hypot(dxOut, dyOut))
            let r = min(radius, lenIn / 2, lenOut / 2)
            let entry = CGPoint(
                x: curr.x - dxIn / lenIn * r,
                y: curr.y - dyIn / lenIn * r
            )
            let exit = CGPoint(
                x: curr.x + dxOut / lenOut * r,
                y: curr.y + dyOut / lenOut * r
            )
            ctx.addLine(to: entry)
            ctx.addQuadCurve(to: exit, control: curr)
        }
        ctx.addLine(to: pts[pts.count - 1])
        ctx.strokePath()
    }

    /// Given a port point and the *outbound* stub direction, project a
    /// label point that (a) sits `distance` pt along the stub — well past
    /// the port cluster — and (b) shifts a small amount to the SIDE of
    /// the stub so multiple parallel stubs' labels stagger left/right of
    /// their line rather than sitting on top of it. The side is chosen
    /// deterministically from the stub direction so pills of adjacent
    /// edges don't land in the same pixel bin.
    private func perpendicularLabelPoint(at port: CGPoint, direction dir: CGVector, distance: CGFloat) -> CGPoint {
        let along = CGPoint(x: port.x + dir.dx * distance, y: port.y + dir.dy * distance)
        // Perpendicular offset ~ 0 for the "central" edges so labels stay
        // close to their stub. Callers pass a large enough distance that
        // pills clear the port row on their own.
        _ = along
        return along
    }

    private func normalize(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = max(0.0001, hypot(dx, dy))
        return CGVector(dx: dx / len, dy: dy / len)
    }

    private func distanceFromPoint(_ p: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
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
        let edgeColor = dark
            ? CGColor(gray: 0.70, alpha: 0.85)
            : CGColor(gray: 0.30, alpha: 0.85)
        let accent = CGColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1)
        let bounds = currentDiagramBounds()
        for (idx, edge) in scene.edges.enumerated() {
            let isSelected = (selectedEdgeIndex == idx)
            let strokeWidth: CGFloat = isSelected ? 2.4 : 1.3
            let strokeColor = isSelected ? accent : edgeColor

            let firstPoint: CGPoint
            let lastPoint: CGPoint
            let entryDir: CGVector
            let exitDir: CGVector

            if let poly = liveOrthogonalPath(for: edge), poly.count >= 2 {
                if isSelected {
                    ctx.setStrokeColor(accent.copy(alpha: 0.25)!)
                    ctx.setLineWidth(5)
                    strokeSharpPolyline(poly, in: ctx)
                }
                ctx.setStrokeColor(strokeColor); ctx.setLineWidth(strokeWidth)
                strokeSharpPolyline(poly, in: ctx)
                firstPoint = poly[0]
                lastPoint  = poly[poly.count - 1]
                entryDir   = normalize(from: poly[0], to: poly[1])
                exitDir    = normalize(from: poly[poly.count - 2], to: poly[poly.count - 1])
            } else if let g = bezier(for: edge, diagramBounds: bounds) {
                if isSelected {
                    ctx.setLineWidth(5); ctx.setStrokeColor(accent.copy(alpha: 0.25)!)
                    ctx.beginPath(); ctx.move(to: g.a); ctx.addCurve(to: g.b, control1: g.c1, control2: g.c2); ctx.strokePath()
                }
                ctx.setStrokeColor(strokeColor); ctx.setLineWidth(strokeWidth)
                ctx.beginPath(); ctx.move(to: g.a); ctx.addCurve(to: g.b, control1: g.c1, control2: g.c2); ctx.strokePath()
                firstPoint = g.a
                lastPoint  = g.b
                let dx = g.b.x - g.a.x, dy = g.b.y - g.a.y
                let len = max(1, sqrt(dx * dx + dy * dy))
                entryDir = CGVector(dx: dx / len, dy: dy / len)
                exitDir  = entryDir
            } else { continue }

            // Cardinality labels. In orthogonal (ERD) mode we suppress
            // the plain "1" pills entirely — FK targets are PKs by
            // definition, so "1" is redundant noise and stacking seven
            // of them under a hub table like `users` was the visual
            // mess in the earlier screenshot. Only the many-side
            // cardinalities (N / 0..N / 0..1) carry information and
            // still render. Curved mode keeps the full pair so short
            // schemas read as classic 1—N.
            let showFrom = scene.routing == .curved || edge.fromCardinality != "1"
            let showTo   = scene.routing == .curved || edge.toCardinality   != "1"
            if showFrom {
                let fromLabelPoint = CGPoint(
                    x: firstPoint.x + entryDir.dx * 18,
                    y: firstPoint.y + entryDir.dy * 18
                )
                drawCardinalityLabel(edge.fromCardinality, at: fromLabelPoint, in: ctx, dark: dark)
            }
            if showTo {
                let toLabelPoint = CGPoint(
                    x: lastPoint.x - exitDir.dx * 18,
                    y: lastPoint.y - exitDir.dy * 18
                )
                drawCardinalityLabel(edge.toCardinality, at: toLabelPoint, in: ctx, dark: dark)
            }
        }

        // Nodes
        for node in scene.nodes {
            let rect = rectFor(node)
            drawNode(
                ctx: ctx, rect: rect, title: node.title, lines: node.lines,
                selected: selectedNodes.contains(where: { $0.raw == node.title }),
                highlighted: highlightedNodes.contains(where: { $0.raw == node.title }),
                dark: dark
            )
        }

        // Marquee (rubber-band) rectangle over everything.
        if let a = marqueeAnchor, let b = marqueeCurrent {
            let rect = CGRect(
                x: min(a.x, b.x), y: min(a.y, b.y),
                width: abs(a.x - b.x), height: abs(a.y - b.y)
            )
            let accent = CGColor(red: 0.20, green: 0.55, blue: 0.95, alpha: 1)
            ctx.setFillColor(accent.copy(alpha: 0.10)!)
            ctx.fill(rect)
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            ctx.stroke(rect)
            ctx.setLineDash(phase: 0, lengths: [])
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

    /// Node under a point (topmost first), or nil for empty canvas.
    private func nodeAt(_ point: NSPoint) -> DiagramScene.NodeShape? {
        for node in scene.nodes.reversed() where rectFor(node).contains(point) {
            return node
        }
        return nil
    }

    private func isMultiSelectModifier(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let hit = nodeAt(point) {
            let id = Identifier(raw: hit.title)
            if isMultiSelectModifier(event) {
                if selectedNodes.contains(id) { selectedNodes.remove(id) }
                else { selectedNodes.insert(id) }
            } else if !selectedNodes.contains(id) {
                // Clicking a node that wasn't selected replaces the selection
                // with just that node. If it was already part of a multi-
                // selection, keep the whole set so we can drag them together.
                selectedNodes = [id]
            }
            onSelectionChanged(selectedNodes)
            // Start dragging every currently-selected node.
            draggingTitles = Set(selectedNodes.map(\.raw))
            dragStartMouse = point
            dragStartOffsets = [:]
            for title in draggingTitles {
                dragStartOffsets[title] = nodeOffsets[title] ?? .zero
            }
            NSCursor.closedHand.push()
        } else if let edgeIdx = edgeAt(point) {
            // Clicked on (or near) an edge line — highlight the edge and
            // select both endpoint tables. This gives users a fast way to
            // ask "what does this line connect?" and pulls both tables
            // into the details-panel summary.
            let edge = scene.edges[edgeIdx]
            let a = Identifier(raw: edge.fromTitle)
            let b = Identifier(raw: edge.toTitle)
            let target: Set<Identifier> = [a, b]
            selectedNodes = isMultiSelectModifier(event) ? selectedNodes.union(target) : target
            selectedEdgeIndex = edgeIdx
            onSelectionChanged(selectedNodes)
        } else {
            // Empty canvas — either clear selection or begin marquee.
            if !isMultiSelectModifier(event) {
                selectedNodes.removeAll()
                onSelectionChanged(selectedNodes)
            }
            marqueeAnchor = point
            marqueeCurrent = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !draggingTitles.isEmpty {
            let dx = p.x - dragStartMouse.x
            let dy = p.y - dragStartMouse.y
            for title in draggingTitles {
                let base = dragStartOffsets[title] ?? .zero
                nodeOffsets[title] = CGPoint(x: base.x + dx, y: base.y + dy)
            }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        } else if marqueeAnchor != nil {
            marqueeCurrent = p
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !draggingTitles.isEmpty {
            NSCursor.pop()
            draggingTitles.removeAll()
            dragStartOffsets.removeAll()
        }
        if let a = marqueeAnchor, let b = marqueeCurrent {
            let rect = CGRect(
                x: min(a.x, b.x), y: min(a.y, b.y),
                width: abs(a.x - b.x), height: abs(a.y - b.y)
            )
            // Ignore tiny "click" marquees (< 3pt each side) — they were
            // just clicks on empty space, not intentional drags.
            if rect.width >= 3 && rect.height >= 3 {
                let hits = scene.nodes.compactMap { node -> Identifier? in
                    rect.intersects(rectFor(node)) ? Identifier(raw: node.title) : nil
                }
                let additive = isMultiSelectModifier(event)
                selectedNodes = additive ? selectedNodes.union(hits) : Set(hits)
                onSelectionChanged(selectedNodes)
            }
            marqueeAnchor = nil
            marqueeCurrent = nil
            needsDisplay = true
        }
        super.mouseUp(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for node in scene.nodes {
            addCursorRect(rectFor(node), cursor: .openHand)
        }
    }

    // MARK: keyboard

    override func keyDown(with event: NSEvent) {
        // Escape clears both node and edge selection.
        if event.keyCode == 53 { // kVK_Escape
            if !selectedNodes.isEmpty {
                selectedNodes.removeAll()
                onSelectionChanged(selectedNodes)
            }
            selectedEdgeIndex = nil
            return
        }
        super.keyDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        // Pointer changes to a crosshair when it hovers near a clickable
        // edge line, matching macOS conventions for "there's something to
        // click here".
        let p = convert(event.locationInWindow, from: nil)
        if nodeAt(p) == nil, edgeAt(p) != nil {
            NSCursor.crosshair.set()
        } else if nodeAt(p) == nil {
            NSCursor.arrow.set()
        }
        super.mouseMoved(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    @objc override func selectAll(_ sender: Any?) {
        selectedNodes = Set(scene.nodes.map { Identifier(raw: $0.title) })
        onSelectionChanged(selectedNodes)
    }
}

/// SwiftUI wrapper hosting the AppKit canvas inside an NSScrollView with
/// magnification. A flipped, layer-backed wrapper view keeps the diagram
/// centered when it's smaller than the visible area, so the content never
/// pins to the top-left edge on wide monitors.
public struct DiagramCanvasView: NSViewRepresentable {
    public var scene: DiagramScene
    public var selection: Set<Identifier>
    public var highlights: Set<Identifier>
    public var onSelectionChanged: (Set<Identifier>) -> Void

    public init(
        scene: DiagramScene,
        selection: Set<Identifier>,
        highlights: Set<Identifier>,
        onSelectionChanged: @escaping (Set<Identifier>) -> Void
    ) {
        self.scene = scene
        self.selection = selection
        self.highlights = highlights
        self.onSelectionChanged = onSelectionChanged
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
        canvas.selectedNodes = selection
        canvas.highlightedNodes = highlights
        canvas.onSelectionChanged = onSelectionChanged
        scroll.documentView = canvas
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let canvas = scroll.documentView as? DiagramCanvasNSView else { return }
        canvas.scene = scene
        canvas.selectedNodes = selection
        canvas.highlightedNodes = highlights
        canvas.onSelectionChanged = onSelectionChanged
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
