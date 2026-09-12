import Foundation
import SchemaModel
import LayoutEngine

/// Cross-platform, dependency-free diagram scene. Concrete rasterization
/// (Core Graphics) and export back-ends (PNG/PDF/SVG) land with the app in
/// M2 and export in M10; keeping the scene here means the same primitives
/// drive both.
public struct DiagramScene: Sendable {
    public struct Rect: Sendable {
        public var x, y, width, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }
    public struct NodeShape: Sendable {
        public var rect: Rect
        public var title: String
        public var lines: [String]
        public init(rect: Rect, title: String, lines: [String] = []) {
            self.rect = rect; self.title = title; self.lines = lines
        }
    }
    public struct EdgeShape: Sendable {
        public var from: (x: Double, y: Double)
        public var to: (x: Double, y: Double)
        public init(from: (x: Double, y: Double), to: (x: Double, y: Double)) {
            self.from = from; self.to = to
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
        var positionByName: [Identifier: NodePosition] = [:]
        for p in layout.positions {
            positionByName[p.node] = p
            let table = schema.tables[p.node]
            let lines = (table?.columns ?? []).map { "\($0.name.raw): \($0.type.displayName)" }
            nodes.append(DiagramScene.NodeShape(
                rect: .init(x: p.x, y: p.y, width: p.width, height: p.height),
                title: p.node.raw,
                lines: lines
            ))
        }
        var edges: [DiagramScene.EdgeShape] = []
        for (_, table) in schema.tables {
            for fk in table.foreignKeys {
                guard let a = positionByName[table.name], let b = positionByName[fk.referencedTable] else { continue }
                edges.append(DiagramScene.EdgeShape(
                    from: (a.x + a.width / 2, a.y + a.height / 2),
                    to: (b.x + b.width / 2, b.y + b.height / 2)
                ))
            }
        }
        return DiagramScene(nodes: nodes, edges: edges)
    }
}
