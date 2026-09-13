import Foundation
import SchemaModel
import LayoutEngine

/// Cross-platform, dependency-free diagram scene. Concrete rasterization
/// (Core Graphics) and export back-ends (PNG/PDF/SVG) share this scene as
/// the single source of truth.
public struct DiagramScene: Sendable {
    public struct Rect: Sendable {
        public var x, y, width, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }
    }
    public struct NodeShape: Sendable {
        public var rect: Rect
        public var title: String
        public var lines: [String]
        public init(rect: Rect, title: String, lines: [String] = []) {
            self.rect = rect; self.title = title; self.lines = lines
        }
    }
    /// A directed edge between two nodes. Rects are carried directly so
    /// renderers can compute clean rect-boundary intersections (no more
    /// lines vanishing into the node body). Cardinality strings sit at each
    /// end. `fromTitle`/`toTitle` name the involved nodes so a live-drag
    /// canvas can rewire the edge to the current node position.
    public struct EdgeShape: Sendable {
        public var fromTitle: String
        public var toTitle: String
        public var fromRect: Rect
        public var toRect: Rect
        public var fromCardinality: String
        public var toCardinality: String
        /// True when the straight line between source and target passes
        /// through another node's bounding box — renderers detour long
        /// edges around the diagram so they don't slice through unrelated
        /// tables.
        public var isLongSpan: Bool
        public init(
            fromTitle: String, toTitle: String,
            fromRect: Rect, toRect: Rect,
            fromCardinality: String = "N",
            toCardinality: String = "1",
            isLongSpan: Bool = false
        ) {
            self.fromTitle = fromTitle; self.toTitle = toTitle
            self.fromRect = fromRect; self.toRect = toRect
            self.fromCardinality = fromCardinality
            self.toCardinality = toCardinality
            self.isLongSpan = isLongSpan
        }
    }
    public var nodes: [NodeShape]
    public var edges: [EdgeShape]
    public init(nodes: [NodeShape] = [], edges: [EdgeShape] = []) {
        self.nodes = nodes; self.edges = edges
    }
}

public enum DiagramRenderer {
    public static func buildScene(_ schema: Schema, layout: LayoutResult) -> DiagramScene {
        var nodes: [DiagramScene.NodeShape] = []
        var rectByName: [Identifier: DiagramScene.Rect] = [:]
        for p in layout.positions {
            let rect = DiagramScene.Rect(x: p.x, y: p.y, width: p.width, height: p.height)
            rectByName[p.node] = rect
            let table = schema.tables[p.node]
            let lines = (table?.columns ?? []).map { "\($0.name.raw): \($0.type.displayName)" }
            nodes.append(DiagramScene.NodeShape(rect: rect, title: p.node.raw, lines: lines))
        }
        var edges: [DiagramScene.EdgeShape] = []
        for (_, table) in schema.tables {
            for fk in table.foreignKeys {
                guard let fromRect = rectByName[table.name],
                      let toRect = rectByName[fk.referencedTable] else { continue }
                let (fromCard, toCard) = cardinality(for: fk, in: table)
                let long = edgeCrossesAnyOtherNode(
                    from: fromRect, to: toRect,
                    excluding: [table.name.raw, fk.referencedTable.raw],
                    nodes: nodes
                )
                edges.append(DiagramScene.EdgeShape(
                    fromTitle: table.name.raw,
                    toTitle: fk.referencedTable.raw,
                    fromRect: fromRect,
                    toRect: toRect,
                    fromCardinality: fromCard,
                    toCardinality: toCard,
                    isLongSpan: long
                ))
            }
        }
        return DiagramScene(nodes: nodes, edges: edges)
    }

    /// Returns true when the straight segment from the source rect center
    /// to the target rect center passes through the bounding box of any
    /// other node.
    private static func edgeCrossesAnyOtherNode(
        from: DiagramScene.Rect,
        to: DiagramScene.Rect,
        excluding titles: Set<String>,
        nodes: [DiagramScene.NodeShape]
    ) -> Bool {
        let ax = from.midX, ay = from.midY
        let bx = to.midX, by = to.midY
        for node in nodes where !titles.contains(node.title) {
            if segmentIntersectsRect(ax: ax, ay: ay, bx: bx, by: by, rect: node.rect) {
                return true
            }
        }
        return false
    }

    private static func segmentIntersectsRect(ax: Double, ay: Double, bx: Double, by: Double, rect: DiagramScene.Rect) -> Bool {
        // Liang–Barsky clipping — returns true if the segment intersects the
        // (padded) rectangle.
        let pad: Double = 4
        let xmin = rect.x - pad, xmax = rect.x + rect.width + pad
        let ymin = rect.y - pad, ymax = rect.y + rect.height + pad
        var t0 = 0.0, t1 = 1.0
        let dx = bx - ax, dy = by - ay
        let p = [-dx, dx, -dy, dy]
        let q = [ax - xmin, xmax - ax, ay - ymin, ymax - ay]
        for i in 0..<4 {
            if p[i] == 0 {
                if q[i] < 0 { return false }
            } else {
                let t = q[i] / p[i]
                if p[i] < 0 { if t > t1 { return false }; if t > t0 { t0 = t } }
                else { if t < t0 { return false }; if t < t1 { t1 = t } }
            }
        }
        return true
    }

    private static func cardinality(for fk: ForeignKeySpec, in owner: Table) -> (String, String) {
        let fkCols = Set(fk.localColumns.map(\.normalized))
        let ownerIsUnique = owner.constraints.contains { c in
            switch c {
            case .primaryKey(let cols, _, _), .unique(let cols, _, _):
                return Set(cols.map(\.normalized)) == fkCols
            default: return false
            }
        }
        let anyNullable = owner.columns.contains { col in
            fkCols.contains(col.name.normalized) && col.nullable
        }
        let ownerCard = ownerIsUnique
            ? (anyNullable ? "0..1" : "1")
            : (anyNullable ? "0..N" : "N")
        return (ownerCard, "1")
    }
}

// MARK: line/rect intersection helper (shared by renderers)

extension DiagramScene.Rect {
    /// Point where a line from the rect's center toward `target` exits this
    /// rect. Used by renderers to draw edges from node border to node
    /// border instead of from center to center.
    public func borderPoint(toward target: (x: Double, y: Double)) -> (x: Double, y: Double) {
        let cx = midX, cy = midY
        let dx = target.x - cx, dy = target.y - cy
        if abs(dx) < 0.0001 && abs(dy) < 0.0001 { return (cx, cy) }
        let hw = width / 2, hh = height / 2
        // Scale factor so that (|dx|*s = hw) or (|dy|*s = hh), pick smaller
        let sx = abs(dx) > 0.0001 ? hw / abs(dx) : .infinity
        let sy = abs(dy) > 0.0001 ? hh / abs(dy) : .infinity
        let s = min(sx, sy)
        return (cx + dx * s, cy + dy * s)
    }
}
