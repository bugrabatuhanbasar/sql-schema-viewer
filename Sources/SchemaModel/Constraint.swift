import Foundation

public enum ReferentialAction: String, Sendable, Codable {
    case noAction
    case restrict
    case cascade
    case setNull
    case setDefault
    case unknown
}

public struct ForeignKeySpec: Hashable, Sendable, Codable {
    public var name: Identifier?
    public var localColumns: [Identifier]
    public var referencedTable: Identifier
    public var referencedColumns: [Identifier]
    public var onDelete: ReferentialAction
    public var onUpdate: ReferentialAction
    public var deferrable: Bool
    public var source: SourceRange

    public init(
        name: Identifier? = nil,
        localColumns: [Identifier],
        referencedTable: Identifier,
        referencedColumns: [Identifier],
        onDelete: ReferentialAction = .noAction,
        onUpdate: ReferentialAction = .noAction,
        deferrable: Bool = false,
        source: SourceRange = .zero
    ) {
        self.name = name
        self.localColumns = localColumns
        self.referencedTable = referencedTable
        self.referencedColumns = referencedColumns
        self.onDelete = onDelete
        self.onUpdate = onUpdate
        self.deferrable = deferrable
        self.source = source
    }
}

public enum Constraint: Hashable, Sendable, Codable {
    case primaryKey(columns: [Identifier], name: Identifier?, source: SourceRange)
    case unique(columns: [Identifier], name: Identifier?, source: SourceRange)
    case foreignKey(ForeignKeySpec)
    case check(expression: String, name: Identifier?, source: SourceRange)
    case notNull(column: Identifier, source: SourceRange)
}
