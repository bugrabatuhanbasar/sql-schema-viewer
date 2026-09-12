import Foundation

public enum TableKind: String, Sendable, Codable {
    case regular
    case temporary
    case external
    case unlogged
}

public enum ParseConfidence: String, Sendable, Codable {
    case complete
    case partial
    case unknown
}

public struct Table: Hashable, Sendable, Codable, Identifiable {
    public var id: String { name.normalized }
    public var name: Identifier
    public var columns: [Column]
    public var constraints: [Constraint]
    public var indexes: [Index]
    public var comment: String?
    public var kind: TableKind
    public var source: SourceRange
    public var confidence: ParseConfidence

    public init(
        name: Identifier,
        columns: [Column] = [],
        constraints: [Constraint] = [],
        indexes: [Index] = [],
        comment: String? = nil,
        kind: TableKind = .regular,
        source: SourceRange = .zero,
        confidence: ParseConfidence = .complete
    ) {
        self.name = name
        self.columns = columns
        self.constraints = constraints
        self.indexes = indexes
        self.comment = comment
        self.kind = kind
        self.source = source
        self.confidence = confidence
    }

    public var primaryKeyColumns: [Identifier] {
        for c in constraints {
            if case .primaryKey(let cols, _, _) = c { return cols }
        }
        return []
    }

    public var foreignKeys: [ForeignKeySpec] {
        constraints.compactMap {
            if case .foreignKey(let fk) = $0 { return fk }
            return nil
        }
    }
}
