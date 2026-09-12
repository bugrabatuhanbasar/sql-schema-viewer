import Foundation

public enum IndexOrder: String, Sendable, Codable { case asc, desc, unspecified }

public struct IndexColumn: Hashable, Sendable, Codable {
    public var column: Identifier
    public var expression: String?
    public var order: IndexOrder

    public init(column: Identifier, expression: String? = nil, order: IndexOrder = .unspecified) {
        self.column = column
        self.expression = expression
        self.order = order
    }
}

public struct Index: Hashable, Sendable, Codable {
    public var name: Identifier?
    public var table: Identifier
    public var columns: [IndexColumn]
    public var unique: Bool
    public var method: String?
    public var predicate: String?
    public var source: SourceRange

    public init(
        name: Identifier? = nil,
        table: Identifier,
        columns: [IndexColumn],
        unique: Bool = false,
        method: String? = nil,
        predicate: String? = nil,
        source: SourceRange = .zero
    ) {
        self.name = name
        self.table = table
        self.columns = columns
        self.unique = unique
        self.method = method
        self.predicate = predicate
        self.source = source
    }
}
