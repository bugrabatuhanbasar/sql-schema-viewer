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
        nodeWidth: Double = 240,
        rowHeight: Double = 18,
        headerHeight: Double = 34,
        horizontalGap: Double = 60,
        verticalGap: Double = 40
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
        nodeWidth: Double = 240,
        rowHeight: Double = 18,
        headerHeight: Double = 34,
        horizontalGap: Double = 60,
        verticalGap: Double = 40
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

        var positions: [NodePosition] = []
        var y: Double = 0
        var maxWidth: Double = 0
        for l in layers {
            let ids = groups[l]!.sorted { $0.normalized < $1.normalized }
            let heights = ids.map { id -> Double in
                let cols = schema.tables[id]?.columns.count ?? 0
                return headerHeight + Double(max(cols, 1)) * rowHeight
            }
            let rowHeightMax = heights.max() ?? headerHeight
            var x: Double = 0
            for (idx, id) in ids.enumerated() {
                let h = heights[idx]
                positions.append(NodePosition(
                    node: id,
                    x: x,
                    y: y,
                    width: nodeWidth,
                    height: h
                ))
                x += nodeWidth + horizontalGap
            }
            maxWidth = max(maxWidth, x - horizontalGap)
            y += rowHeightMax + verticalGap
        }
        return LayoutResult(
            positions: positions,
            contentSize: (max(maxWidth, nodeWidth), max(y - verticalGap, headerHeight))
        )
    }
}
