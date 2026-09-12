import Foundation
import SchemaModel

/// Result of parsing a whole source buffer into a `Schema`. Every dialect
/// parser and the DBML parser return this so the caller can merge partial
/// results and diagnostics uniformly.
public struct ParseResult<T: Sendable>: Sendable {
    public var value: T
    public var diagnostics: [Diagnostic]

    public init(value: T, diagnostics: [Diagnostic] = []) {
        self.value = value
        self.diagnostics = diagnostics
    }
}

public protocol StatementParser: Sendable {
    static var dialect: Dialect { get }
    func parse(source: String, file: URL?) -> ParseResult<Schema>
}
