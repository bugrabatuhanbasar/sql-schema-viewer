import Foundation
import SchemaModel
import SQLLexer
import ParserCore

public struct OracleParser: StatementParser {
    public static var dialect: Dialect { .oracle }
    public init() {}
    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        let buffer = SourceBuffer(source, file: file)
        let splitter = StatementSplitter(config: .oracle)
        let slices = splitter.split(buffer)
        var schema = Schema(dialect: .oracle)
        schema.stats.skippedStatements = slices.count
        return ParseResult(value: schema)
    }
}
