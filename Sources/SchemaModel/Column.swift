import Foundation

public enum GeneratedKind: String, Sendable, Codable {
    case always
    case byDefault
    case stored
    case virtual
}

public struct Column: Hashable, Sendable, Codable, Identifiable {
    public var id: String { name.normalized }
    public var name: Identifier
    public var type: DataType
    public var nullable: Bool
    public var defaultExpression: String?
    public var comment: String?
    public var generated: GeneratedKind?
    public var source: SourceRange

    public init(
        name: Identifier,
        type: DataType,
        nullable: Bool = true,
        defaultExpression: String? = nil,
        comment: String? = nil,
        generated: GeneratedKind? = nil,
        source: SourceRange = .zero
    ) {
        self.name = name
        self.type = type
        self.nullable = nullable
        self.defaultExpression = defaultExpression
        self.comment = comment
        self.generated = generated
        self.source = source
    }
}
