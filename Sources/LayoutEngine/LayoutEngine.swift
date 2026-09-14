import Foundation
import SchemaModel

public struct NodePosition: Sendable, Equatable {
    public var node: Identifier
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(node: Identifier, x: Double, y: Double, width: Double, height: Double) {
        self.node = node; self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct LayoutResult: Sendable {
    public var positions: [NodePosition]
    public var contentSize: (width: Double, height: Double)
    public init(positions: [NodePosition] = [], contentSize: (Double, Double) = (0, 0)) {
        self.positions = positions
        self.contentSize = contentSize
    }
}

/// Layered layout for foreign-key DAGs. Nodes with no incoming FKs go in
/// layer 0; each remaining node's layer is 1 + max(parent layers). Cycles
/// are broken by placing back-edge targets one layer below their referrer.
/// Node heights account for column counts so long tables don't overlap.
public enum LayoutEngine {

    /// Public entrypoint. Uses layered layout by default.
    public static func layout(
        _ schema: Schema,
        nodeWidth: Double = 260,
        rowHeight: Double = 18,
        headerHeight: Double = 34,
        horizontalGap: Double = 110,
        verticalGap: Double = 140
    ) -> LayoutResult {
        layered(
            schema,
            nodeWidth: nodeWidth,
            rowHeight: rowHeight,
            headerHeight: headerHeight,
            horizontalGap: horizontalGap,
            verticalGap: verticalGap
        )
    }

    public static func layered(
        _ schema: Schema,
        nodeWidth: Double = 260,
        rowHeight: Double = 18,
        headerHeight: Double = 34,
        horizontalGap: Double = 110,
        verticalGap: Double = 140
    ) -> LayoutResult {
        let names = schema.tables.keys.sorted { $0.normalized < $1.normalized }
        if names.isEmpty { return LayoutResult() }

        var parents: [Identifier: Set<Identifier>] = [:]
        for id in names { parents[id] = [] }
        for (_, table) in schema.tables {
            for fk in table.foreignKeys where fk.referencedTable != table.name {
                if schema.tables[fk.referencedTable] != nil {
                    parents[table.name, default: []].insert(fk.referencedTable)
                }
            }
        }

        // Longest-path layering with cycle tolerance: iterate until a stable
        // assignment or a bounded number of passes.
        var layer: [Identifier: Int] = Dictionary(uniqueKeysWithValues: names.map { ($0, 0) })
        let maxIterations = max(4, names.count)
        for _ in 0..<maxIterations {
            var changed = false
            for id in names {
                let p = parents[id] ?? []
                let candidate = (p.compactMap { layer[$0] }.max() ?? -1) + 1
                if candidate > (layer[id] ?? 0) {
                    layer[id] = candidate
                    changed = true
                }
            }
            if !changed { break }
        }

        var groups: [Int: [Identifier]] = [:]
        for id in names { groups[layer[id]!, default: []].append(id) }
        let layers = groups.keys.sorted()

        // Order nodes within each layer using a median heuristic over the
        // previous layer's positions (classic Sugiyama step). This dramatically
        // cuts edge crossings vs. an alphabetical order: children sit close
        // to the horizontal position of their parents, so an edge from A
        // (layer N) to B (layer N+1) tends to run near-straight instead of
        // sweeping across other nodes on the way down.
        // Build per-layer ordering + geometry. Positions are assigned as we
        // go, so each layer's node targets the barycenter of its parents'
        // *actual* x positions in previous layers — a lightweight Sugiyama
        // coordinate-assignment. Overlap is prevented by sweeping left to
        // right with a minimum step of nodeWidth + horizontalGap.
        var perLayerIds: [[Identifier]] = []
        var perLayerHeights: [[Double]] = []
        var perLayerXs: [[Double]] = []
        var xByName: [Identifier: Double] = [:]

        func height(of id: Identifier) -> Double {
            let cols = schema.tables[id]?.columns.count ?? 0
            return headerHeight + Double(max(cols, 1)) * rowHeight
        }

        for (li, l) in layers.enumerated() {
            var ids = groups[l]!

            if li == 0 {
                // Root layer: alphabetical, laid out left-to-right from 0.
                ids.sort { $0.normalized < $1.normalized }
                var xs: [Double] = []
                var x: Double = 0
                for _ in ids { xs.append(x); x += nodeWidth + horizontalGap }
                for (i, id) in ids.enumerated() { xByName[id] = xs[i] }
                perLayerIds.append(ids)
                perLayerHeights.append(ids.map(height))
                perLayerXs.append(xs)
                continue
            }

            // Later layers: compute each node's target x = barycenter of its
            // parents' xByName, then pack left-to-right in target order.
            var targets: [(id: Identifier, target: Double)] = ids.map { id in
                let pxs = (parents[id] ?? []).compactMap { xByName[$0] }
                let t = pxs.isEmpty ? .greatestFiniteMagnitude : pxs.reduce(0, +) / Double(pxs.count)
                return (id, t)
            }
            // Sort by target, then alphabetical for ties.
            targets.sort {
                if $0.target != $1.target { return $0.target < $1.target }
                return $0.id.normalized < $1.id.normalized
            }
            var xs: [Double] = Array(repeating: 0, count: targets.count)
            var prevRight = -Double.infinity
            for (i, pair) in targets.enumerated() {
                let x = max(pair.target, prevRight + horizontalGap)
                xs[i] = x
                prevRight = x + nodeWidth
            }
            ids = targets.map(\.id)
            for (i, id) in ids.enumerated() { xByName[id] = xs[i] }
            perLayerIds.append(ids)
            perLayerHeights.append(ids.map(height))
            perLayerXs.append(xs)
        }

        // Global left-align so every layer starts at x=0 (avoid negative x
        // if the barycenter pass pushed a layer left of the roots).
        let minX = perLayerXs.flatMap { $0 }.min() ?? 0
        if minX < 0 {
            let shift = -minX
            for li in perLayerXs.indices {
                for i in perLayerXs[li].indices { perLayerXs[li][i] += shift }
            }
            for (name, x) in xByName { xByName[name] = x + shift }
        }

        // Compute overall content width from the rightmost node right edge.
        var maxRight: Double = 0
        for li in perLayerXs.indices {
            for x in perLayerXs[li] { maxRight = max(maxRight, x + nodeWidth) }
        }

        var positions: [NodePosition] = []
        var y: Double = 0
        for (li, ids) in perLayerIds.enumerated() {
            let heights = perLayerHeights[li]
            let xs = perLayerXs[li]
            let rowHeightMax = heights.max() ?? headerHeight
            for (idx, id) in ids.enumerated() {
                let h = heights[idx]
                let rowY = y + (rowHeightMax - h) / 2
                positions.append(NodePosition(
                    node: id, x: xs[idx], y: rowY,
                    width: nodeWidth, height: h
                ))
            }
            y += rowHeightMax + verticalGap
        }
        return LayoutResult(
            positions: positions,
            contentSize: (max(maxRight, nodeWidth), max(y - verticalGap, headerHeight))
        )
    }
}

