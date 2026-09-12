import Foundation

public enum RoutineKind: String, Sendable, Codable {
    case function
    case procedure
}

public enum ParameterMode: String, Sendable, Codable {
    case input
    case output
    case inout_
    case unknown
}

public struct Parameter: Hashable, Sendable, Codable {
    public var name: Identifier?
    public var type: DataType
    public var mode: ParameterMode
    public var defaultExpression: String?

    public init(name: Identifier? = nil, type: DataType, mode: ParameterMode = .input, defaultExpression: String? = nil) {
        self.name = name
        self.type = type
        self.mode = mode
        self.defaultExpression = defaultExpression
    }
}

public struct Routine: Hashable, Sendable, Codable, Identifiable {
    public var id: String { name.normalized }
    public var name: Identifier
    public var kind: RoutineKind
    public var language: String?
    public var parameters: [Parameter]
    public var returnType: DataType?
    public var bodySQL: String
    public var referencedTables: [Reference]
    public var source: SourceRange
    public var confidence: ParseConfidence

    public init(
        name: Identifier,
        kind: RoutineKind,
        language: String? = nil,
        parameters: [Parameter] = [],
        returnType: DataType? = nil,
        bodySQL: String = "",
        referencedTables: [Reference] = [],
        source: SourceRange = .zero,
        confidence: ParseConfidence = .complete
    ) {
        self.name = name
        self.kind = kind
        self.language = language
        self.parameters = parameters
        self.returnType = returnType
        self.bodySQL = bodySQL
        self.referencedTables = referencedTables
        self.source = source
        self.confidence = confidence
    }
}
