import Foundation
import SchemaModel

/// Builds a directed dependency graph over tables, views, triggers, and
/// routines. Full implementation lands in M7.
public struct DependencyGraph: Sendable {
    public var edges: [DependencyEdge]
    public init(edges: [DependencyEdge] = []) { self.edges = edges }
}

public struct DependencyEdge: Hashable, Sendable {
    public var from: Identifier
    public var to: Identifier
    public var kind: ReferenceKind
    public var confidence: ParseConfidence

    public init(from: Identifier, to: Identifier, kind: ReferenceKind, confidence: ParseConfidence) {
        self.from = from; self.to = to; self.kind = kind; self.confidence = confidence
    }
}

public enum DependencyAnalyzer {
    public static func analyze(_ schema: Schema) -> DependencyGraph {
        var edges: [DependencyEdge] = []
        for (_, table) in schema.tables {
            for fk in table.foreignKeys {
                edges.append(DependencyEdge(
                    from: table.name,
                    to: fk.referencedTable,
                    kind: .table,
                    confidence: .complete
                ))
            }
        }
        return DependencyGraph(edges: edges)
    }
}
