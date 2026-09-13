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
    }
    public struct NodeShape: Sendable {
        public var rect: Rect
        public var title: String
        public var lines: [String]
        public init(rect: Rect, title: String, lines: [String] = []) {
            self.rect = rect; self.title = title; self.lines = lines
        }
    }
    /// A directed edge from `from` (the FK owner) to `to` (the referenced
    /// side). `fromCardinality` is written at the owner-side endpoint,
    /// `toCardinality` at the referenced-side endpoint. Typical values:
    /// "1", "N", "0..1".
    public struct EdgeShape: Sendable {
        public var from: (x: Double, y: Double)
        public var to: (x: Double, y: Double)
        public var fromCardinality: String
        public var toCardinality: String
        public init(
            from: (x: Double, y: Double),
            to: (x: Double, y: Double),
            fromCardinality: String = "N",
            toCardinality: String = "1"
        ) {
            self.from = from; self.to = to
            self.fromCardinality = fromCardinality
            self.toCardinality = toCardinality
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
                let (fromCard, toCard) = cardinality(for: fk, in: table, target: schema.tables[fk.referencedTable])
                edges.append(DiagramScene.EdgeShape(
                    from: (a.x + a.width / 2, a.y + a.height / 2),
                    to: (b.x + b.width / 2, b.y + b.height / 2),
                    fromCardinality: fromCard,
                    toCardinality: toCard
                ))
            }
        }
        return DiagramScene(nodes: nodes, edges: edges)
    }

    /// Cardinality inference for an FK from owner-side to referenced-side.
    /// - Referenced side is almost always "1" (FK references a PK/UNIQUE
    ///   column set).
    /// - Owner side is "N" unless the FK columns themselves are covered by
    ///   a PK or UNIQUE constraint on the owner — then the relationship is
    ///   one-to-one, so the owner side is also "1".
    /// - Optionality: if any FK local column is nullable, the owner side is
    ///   prefixed with "0..".
    private static func cardinality(
        for fk: ForeignKeySpec,
        in owner: Table,
        target: Table?
    ) -> (fromCard: String, toCard: String) {
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
        // Referenced side: PK by definition → "1". If the FK references a
        // known table but the column set doesn't cover its PK, still 1
        // (uniqueness is required by SQL for FK targets).
        _ = target
        return (ownerCard, "1")
    }
}
