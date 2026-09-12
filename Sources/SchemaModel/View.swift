import Foundation

public enum ReferenceKind: String, Sendable, Codable {
    case table
    case view
    case routine
    case trigger
    case column
}

public struct Reference: Hashable, Sendable, Codable {
    public var target: Identifier
    public var kind: ReferenceKind
    public var confidence: ParseConfidence
    public var source: SourceRange

    public init(target: Identifier, kind: ReferenceKind, confidence: ParseConfidence = .complete, source: SourceRange = .zero) {
        self.target = target
        self.kind = kind
        self.confidence = confidence
        self.source = source
    }
}

public struct View: Hashable, Sendable, Codable, Identifiable {
    public var id: String { name.normalized }
    public var name: Identifier
    public var materialized: Bool
    public var definitionSQL: String
    public var referencedTables: [Reference]
    public var referencedViews: [Reference]
    public var source: SourceRange
    public var confidence: ParseConfidence

    public init(
        name: Identifier,
        materialized: Bool = false,
        definitionSQL: String = "",
        referencedTables: [Reference] = [],
        referencedViews: [Reference] = [],
        source: SourceRange = .zero,
        confidence: ParseConfidence = .complete
    ) {
        self.name = name
        self.materialized = materialized
        self.definitionSQL = definitionSQL
        self.referencedTables = referencedTables
        self.referencedViews = referencedViews
        self.source = source
        self.confidence = confidence
    }
}
