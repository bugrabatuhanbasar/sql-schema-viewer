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
    /// Build the full dependency graph:
    /// - FK edges between tables
    /// - View / matview → table (and view → view) edges via body scanning
    /// - Trigger → table edges (associated table + body scan)
    /// - Routine (function/procedure) → table edges via body scan
    /// Body-derived references honor `.partial` confidence when the body
    /// contains EXECUTE IMMEDIATE / dynamic SQL constructs.
    public static func analyze(_ schema: Schema) -> DependencyGraph {
        var edges: [DependencyEdge] = []
        let scanner = BodyScanner()

        for (_, table) in schema.tables {
            for fk in table.foreignKeys {
                edges.append(DependencyEdge(
                    from: table.name, to: fk.referencedTable,
                    kind: .table, confidence: .complete
                ))
            }
        }
        for (_, view) in schema.views {
            let result = scanner.scan(body: view.definitionSQL)
            for r in result.reads {
                let target = matchTarget(schema, id: r.target)
                edges.append(DependencyEdge(from: view.name, to: target.id, kind: target.kind, confidence: r.confidence))
            }
        }
        for (_, tr) in schema.triggers {
            // Trigger is anchored to its owning table.
            if !tr.table.raw.isEmpty {
                edges.append(DependencyEdge(from: tr.name, to: tr.table, kind: .table, confidence: .complete))
            }
            let result = scanner.scan(body: tr.bodySQL)
            for r in result.reads {
                let target = matchTarget(schema, id: r.target)
                edges.append(DependencyEdge(from: tr.name, to: target.id, kind: target.kind, confidence: r.confidence))
            }
            for r in result.writes {
                let target = matchTarget(schema, id: r.target)
                edges.append(DependencyEdge(from: tr.name, to: target.id, kind: target.kind, confidence: r.confidence))
            }
        }
        for (_, routine) in schema.routines {
            let result = scanner.scan(body: routine.bodySQL)
            for r in result.reads + result.writes {
                let target = matchTarget(schema, id: r.target)
                edges.append(DependencyEdge(from: routine.name, to: target.id, kind: target.kind, confidence: r.confidence))
            }
        }
        return DependencyGraph(edges: dedupe(edges))
    }

    /// Try to resolve a raw reference to a known table/view/routine name in
    /// the schema; if not found, return it as a table reference (dangling
    /// references are surfaced by QualityChecks, not here).
    private static func matchTarget(_ schema: Schema, id: Identifier) -> (id: Identifier, kind: ReferenceKind) {
        if schema.tables[id] != nil { return (id, .table) }
        if schema.views[id] != nil { return (id, .view) }
        if schema.routines[id] != nil { return (id, .routine) }
        // Try without schema qualification
        let bare = Identifier(raw: id.raw, quoted: id.quoted)
        if schema.tables[bare] != nil { return (bare, .table) }
        if schema.views[bare] != nil { return (bare, .view) }
        if schema.routines[bare] != nil { return (bare, .routine) }
        return (id, .table)
    }

    private static func dedupe(_ edges: [DependencyEdge]) -> [DependencyEdge] {
        var seen = Set<DependencyEdge>()
        var out: [DependencyEdge] = []
        for e in edges where !seen.contains(e) { seen.insert(e); out.append(e) }
        return out
    }
}
