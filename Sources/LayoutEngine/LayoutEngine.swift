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

/// Layered layout for FK DAGs.
///
/// # Design goals
///
/// After a long series of edge-routing patches failed to un-stack edges on
/// hub tables, we redesigned the placement pass itself. The rules are:
///
/// 1. **Uniform grid inside a layer.** Tables in the same layer sit on
///    fixed column x's — no barycenter attraction. Barycenter looked
///    tidier for tiny schemas but on real schemas it pulled multiple
///    children of a hub onto near-identical x's, which then made every
///    downstream edge fan out from the same pixel. Uniform grid keeps
///    them well separated.
///
/// 2. **Alphabetical ordering inside a layer.** Deterministic and readable
///    — users always find `posts` before `users` on the same row.
///
/// 3. **Dynamic vertical gap per layer transition.** The gap between two
///    adjacent layers grows with the number of edges that cross it. If 12
///    edges cross the gap between layer 1 and layer 2, we allocate
///    `baseGap + 12 * laneStep` pt so the orthogonal router has room to
///    stack every edge on its own horizontal rail without them piling up.
///
/// 4. **Generous outer padding.** The whole diagram sits inside a padded
///    frame so the router can safely arc a long-span edge around the
///    outside without clipping the frame.
public enum LayoutEngine {

    public static func layout(
        _ schema: Schema,
        nodeWidth: Double = 260,
        rowHeight: Double = 18,
        headerHeight: Double = 34,
        horizontalGap: Double = 140,
        baseVerticalGap: Double = 120,
        laneStep: Double = 22,
        outerPadding: Double = 200
    ) -> LayoutResult {
        layered(
            schema,
            nodeWidth: nodeWidth,
            rowHeight: rowHeight,
            headerHeight: headerHeight,
            horizontalGap: horizontalGap,
            baseVerticalGap: baseVerticalGap,
            laneStep: laneStep,
            outerPadding: outerPadding
        )
    }

    public static func layered(
        _ schema: Schema,
        nodeWidth: Double = 260,
        rowHeight: Double = 18,
        headerHeight: Double = 34,
        horizontalGap: Double = 140,
        baseVerticalGap: Double = 120,
        laneStep: Double = 22,
        outerPadding: Double = 200
    ) -> LayoutResult {
        let names = schema.tables.keys.sorted { $0.normalized < $1.normalized }
        if names.isEmpty { return LayoutResult() }

        // Adjacency (parents) for longest-path layering.
        var parents: [Identifier: Set<Identifier>] = [:]
        for id in names { parents[id] = [] }
        for (_, table) in schema.tables {
            for fk in table.foreignKeys where fk.referencedTable != table.name {
                if schema.tables[fk.referencedTable] != nil {
                    parents[table.name, default: []].insert(fk.referencedTable)
                }
            }
        }

        // Longest-path layering with cycle tolerance.
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
        let layerKeys = groups.keys.sorted()

        // Each layer: alphabetical ordering, uniform grid across a shared
        // column pitch. All layers use the SAME column pitch so children
        // and grandparents line up visually.
        let columnPitch = nodeWidth + horizontalGap
        // Widest layer sets the total column count.
        let maxLayerCount = layerKeys.map { groups[$0]!.count }.max() ?? 1
        let totalContentWidth = Double(maxLayerCount) * nodeWidth
            + Double(max(maxLayerCount - 1, 0)) * horizontalGap

        func height(of id: Identifier) -> Double {
            let cols = schema.tables[id]?.columns.count ?? 0
            return headerHeight + Double(max(cols, 1)) * rowHeight
        }

        // Pre-compute per-layer arrays.
        var perLayerIds: [[Identifier]] = []
        var perLayerHeights: [[Double]] = []
        for l in layerKeys {
            let ids = groups[l]!.sorted { $0.normalized < $1.normalized }
            perLayerIds.append(ids)
            perLayerHeights.append(ids.map(height))
        }

        // Count edges crossing each layer boundary — used to widen the
        // vertical gap dynamically so the orthogonal router has enough
        // horizontal rails to unpack every parallel edge.
        //
        // Each FK contributes to every gap between its source layer and
        // target layer. A short-hop parent→child crosses one gap; a
        // Layer 3 → Layer 0 edge crosses three.
        var idToLayer: [Identifier: Int] = [:]
        for (li, ids) in perLayerIds.enumerated() {
            for id in ids { idToLayer[id] = li }
        }
        var edgesAcrossGap: [Int: Int] = [:]
        for (_, table) in schema.tables {
            guard let srcLayer = idToLayer[table.name] else { continue }
            for fk in table.foreignKeys {
                guard let dstLayer = idToLayer[fk.referencedTable] else { continue }
                let lo = min(srcLayer, dstLayer)
                let hi = max(srcLayer, dstLayer)
                if lo == hi { continue }
                for g in lo..<hi { edgesAcrossGap[g, default: 0] += 1 }
            }
        }

        // Place nodes. Each layer gets its own y = previous.y + previous
        // rowHeight + gapBetween(previousLayer, thisLayer).
        var positions: [NodePosition] = []
        var y: Double = outerPadding
        var maxRight: Double = 0
        for (li, ids) in perLayerIds.enumerated() {
            let heights = perLayerHeights[li]
            let rowHeightMax = heights.max() ?? headerHeight

            // Centre the row within the total content width by using half
            // of the leftover space as the starting x. Even for the widest
            // layer this leaves a 0-pt margin; narrower layers land nicely
            // centred within the diagram frame.
            let layerRowWidth = Double(ids.count) * nodeWidth
                + Double(max(ids.count - 1, 0)) * horizontalGap
            let rowLeft = outerPadding + (totalContentWidth - layerRowWidth) / 2

            var x = rowLeft
            for (i, id) in ids.enumerated() {
                let h = heights[i]
                let rowY = y + (rowHeightMax - h) / 2
                positions.append(NodePosition(
                    node: id, x: x, y: rowY,
                    width: nodeWidth, height: h
                ))
                x += columnPitch
                maxRight = max(maxRight, x - horizontalGap)
            }
            // Move down to the next layer.
            if li < perLayerIds.count - 1 {
                let crossing = edgesAcrossGap[li] ?? 0
                let dynamicGap = baseVerticalGap + Double(crossing) * laneStep
                y += rowHeightMax + dynamicGap
            } else {
                y += rowHeightMax
            }
        }

        let contentWidth = maxRight + outerPadding
        let contentHeight = y + outerPadding
        return LayoutResult(
            positions: positions,
            contentSize: (contentWidth, contentHeight)
        )
    }
}
