import Foundation
import SchemaModel

/// The V1 quality checks listed in the spec. Every check produces warnings
/// only — nothing here modifies the schema, and nothing surfaces a change
/// to the source file. Each `Diagnostic` carries a stable `code` so the UI
/// can group and route them.
public enum QualityChecks {
    public static func run(on schema: Schema) -> [Diagnostic] {
        var out: [Diagnostic] = []
        out.append(contentsOf: missingPrimaryKeys(schema))
        out.append(contentsOf: incompatibleFKTypes(schema))
        out.append(contentsOf: unindexedFKColumns(schema))
        out.append(contentsOf: suspectedFKColumns(schema))
        out.append(contentsOf: duplicateNames(schema))
        out.append(contentsOf: orphanTables(schema))
        out.append(contentsOf: partialObjects(schema))
        out.append(contentsOf: circularDependencies(schema))
        out.append(contentsOf: danglingReferences(schema))
        return out
    }

    // 1. Tables without primary keys
    static func missingPrimaryKeys(_ s: Schema) -> [Diagnostic] {
        s.tables.values.compactMap { t in
            t.primaryKeyColumns.isEmpty
                ? Diagnostic(severity: .warning, code: "W0010",
                             message: "Table \(t.name.raw) has no primary key",
                             source: t.source)
                : nil
        }
    }

    // 2. FK pairs with incompatible data types
    static func incompatibleFKTypes(_ s: Schema) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for (_, t) in s.tables {
            for fk in t.foreignKeys {
                guard let ref = s.tables[fk.referencedTable] else { continue }
                for (i, localName) in fk.localColumns.enumerated() {
                    guard let refName = fk.referencedColumns[safe: i],
                          let localCol = t.columns.first(where: { $0.name.normalized == localName.normalized }),
                          let refCol = ref.columns.first(where: { $0.name.normalized == refName.normalized })
                    else { continue }
                    if !localCol.type.isCompatible(with: refCol.type) {
                        out.append(Diagnostic(
                            severity: .warning, code: "W0011",
                            message: "FK \(t.name.raw).\(localName.raw) (\(localCol.type.displayName)) is incompatible with \(ref.name.raw).\(refName.raw) (\(refCol.type.displayName))",
                            source: fk.source
                        ))
                    }
                }
            }
        }
        return out
    }

    // 3. FK columns without a matching index
    static func unindexedFKColumns(_ s: Schema) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for (_, t) in s.tables {
            for fk in t.foreignKeys {
                let fkCols = Set(fk.localColumns.map(\.normalized))
                let indexed = t.indexes.contains { idx in
                    let leading = idx.columns.first.map(\.column.normalized)
                    return leading.map { fkCols.contains($0) } ?? false
                }
                // Also count PK/UNIQUE constraints as an implicit index on their columns.
                let uniqueCovered = t.constraints.contains { c in
                    switch c {
                    case .primaryKey(let cols, _, _), .unique(let cols, _, _):
                        return cols.first.map { fkCols.contains($0.normalized) } ?? false
                    default: return false
                    }
                }
                if !indexed && !uniqueCovered {
                    out.append(Diagnostic(
                        severity: .warning, code: "W0012",
                        message: "FK column(s) \(fk.localColumns.map(\.raw).joined(separator: ", ")) on \(t.name.raw) are not indexed",
                        source: fk.source
                    ))
                }
            }
        }
        return out
    }

    // 4. Columns like *_id that are not part of any FK
    static func suspectedFKColumns(_ s: Schema) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for (_, t) in s.tables {
            let fkCols = Set(t.foreignKeys.flatMap { $0.localColumns.map(\.normalized) })
            for col in t.columns
                where col.name.normalized.hasSuffix("_id")
                    && !fkCols.contains(col.name.normalized)
                    && !t.primaryKeyColumns.contains(where: { $0.normalized == col.name.normalized }) {
                out.append(Diagnostic(
                    severity: .warning, code: "W0013",
                    message: "Column \(t.name.raw).\(col.name.raw) looks like a foreign key but has no FK constraint",
                    source: col.source
                ))
            }
        }
        return out
    }

    // 5. Duplicate names in same scope
    static func duplicateNames(_ s: Schema) -> [Diagnostic] {
        var out: [Diagnostic] = []
        // Tables share a namespace with views in most DBs; flag collisions.
        var seenTop = Set<String>()
        for name in s.tables.keys.map(\.normalized) + s.views.keys.map(\.normalized) {
            if !seenTop.insert(name).inserted {
                out.append(Diagnostic(severity: .warning, code: "W0014",
                                      message: "Duplicate table/view name \(name)",
                                      source: .zero))
            }
        }
        for (_, t) in s.tables {
            var seen = Set<String>()
            for col in t.columns where !seen.insert(col.name.normalized).inserted {
                out.append(Diagnostic(
                    severity: .warning, code: "W0014",
                    message: "Duplicate column \(col.name.raw) in table \(t.name.raw)",
                    source: col.source
                ))
            }
        }
        return out
    }

    // 6. Tables without any relationship (in or out)
    static func orphanTables(_ s: Schema) -> [Diagnostic] {
        let referenced = Set(s.tables.values.flatMap { $0.foreignKeys.map(\.referencedTable.normalized) })
        return s.tables.values.compactMap { t in
            let hasOutgoing = !t.foreignKeys.isEmpty
            let hasIncoming = referenced.contains(t.name.normalized)
            if hasOutgoing || hasIncoming { return nil }
            return Diagnostic(
                severity: .warning, code: "W0015",
                message: "Table \(t.name.raw) has no relationships",
                source: t.source
            )
        }
    }

    // 7. Missing or unparsed constraints — surface tables with .partial
    // confidence so users know some info was dropped.
    static func partialObjects(_ s: Schema) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for (_, t) in s.tables where t.confidence == .partial {
            out.append(Diagnostic(severity: .info, code: "W0001",
                                  message: "Table \(t.name.raw) parsed with missing details",
                                  source: t.source))
        }
        return out
    }

    // 8. Possible circular dependencies among FK edges
    static func circularDependencies(_ s: Schema) -> [Diagnostic] {
        var adjacency: [Identifier: [Identifier]] = [:]
        for (_, t) in s.tables {
            for fk in t.foreignKeys where fk.referencedTable != t.name {
                adjacency[t.name, default: []].append(fk.referencedTable)
            }
        }
        var out: [Diagnostic] = []
        var visited = Set<Identifier>()
        var onStack = Set<Identifier>()
        var cycleReported = Set<Set<Identifier>>()
        func dfs(_ node: Identifier, _ path: inout [Identifier]) {
            visited.insert(node); onStack.insert(node); path.append(node)
            for next in adjacency[node, default: []] {
                if !visited.contains(next) {
                    dfs(next, &path)
                } else if onStack.contains(next), let idx = path.firstIndex(of: next) {
                    let cycle = Set(path[idx...])
                    if !cycleReported.contains(cycle) {
                        cycleReported.insert(cycle)
                        out.append(Diagnostic(
                            severity: .warning, code: "W0017",
                            message: "Possible circular dependency: \(cycle.map(\.raw).sorted().joined(separator: " → "))",
                            source: .zero
                        ))
                    }
                }
            }
            _ = onStack.remove(node); path.removeLast()
        }
        for node in adjacency.keys {
            if !visited.contains(node) { var p: [Identifier] = []; dfs(node, &p) }
        }
        return out
    }

    // 9. References to unknown tables or columns
    static func danglingReferences(_ s: Schema) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for (_, t) in s.tables {
            for fk in t.foreignKeys {
                if s.tables[fk.referencedTable] == nil,
                   s.tables[Identifier(raw: fk.referencedTable.raw)] == nil {
                    out.append(Diagnostic(
                        severity: .warning, code: "W0016",
                        message: "FK on \(t.name.raw) references unknown table \(fk.referencedTable.raw)",
                        source: fk.source
                    ))
                    continue
                }
                let ref = s.tables[fk.referencedTable] ?? s.tables[Identifier(raw: fk.referencedTable.raw)]
                guard let ref else { continue }
                for col in fk.referencedColumns
                    where !ref.columns.contains(where: { $0.name.normalized == col.normalized }) {
                    out.append(Diagnostic(
                        severity: .warning, code: "W0016",
                        message: "FK on \(t.name.raw) references unknown column \(ref.name.raw).\(col.raw)",
                        source: fk.source
                    ))
                }
            }
        }
        return out
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}
