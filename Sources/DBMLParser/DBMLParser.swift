import Foundation
import SchemaModel
import ParserCore

public struct DBMLParser: StatementParser {
    public static var dialect: Dialect { .dbml }
    public init() {}
    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        // Full implementation lands in M6.
        return ParseResult(value: Schema(dialect: .dbml))
    }
}

/// Serialize a parsed `Schema` back into DBML text. Lossy transformations
/// are reported via `.info` diagnostics.
public enum DBMLExporter {
    public static func export(_ schema: Schema) -> ParseResult<String> {
        // Full implementation lands in M6.
        return ParseResult(value: "// DBML export stub\n")
    }
}
