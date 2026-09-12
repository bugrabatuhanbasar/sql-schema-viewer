import Foundation
import SchemaModel
import SQLLexer
import ParserCore

public struct SQLiteParser: StatementParser {
    public static var dialect: Dialect { .sqlite }
    public init() {}
    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        let buffer = SourceBuffer(source, file: file)
        let splitter = StatementSplitter(config: .sqlite)
        let slices = splitter.split(buffer)
        var schema = Schema(dialect: .sqlite)
        schema.stats.skippedStatements = slices.count
        return ParseResult(value: schema)
    }
}
