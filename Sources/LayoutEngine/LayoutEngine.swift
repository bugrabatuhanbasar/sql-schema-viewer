import Foundation
import SchemaModel

public struct NodePosition: Sendable {
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
    public init(positions: [NodePosition] = []) { self.positions = positions }
}

/// Full layered / force-directed layout lands in M8. This M1 stub places
/// tables in a deterministic grid so early integration tests can still
/// render a scene.
public enum LayoutEngine {
    public static func layout(_ schema: Schema, nodeWidth: Double = 220, nodeHeight: Double = 120, gap: Double = 40) -> LayoutResult {
        let tables = schema.tables.values.sorted { $0.name.normalized < $1.name.normalized }
        let columns = Int(ceil(sqrt(Double(max(tables.count, 1)))))
        var positions: [NodePosition] = []
        for (i, t) in tables.enumerated() {
            let row = i / columns
            let col = i % columns
            positions.append(NodePosition(
                node: t.name,
                x: Double(col) * (nodeWidth + gap),
                y: Double(row) * (nodeHeight + gap),
                width: nodeWidth,
                height: nodeHeight
            ))
        }
        return LayoutResult(positions: positions)
    }
}
