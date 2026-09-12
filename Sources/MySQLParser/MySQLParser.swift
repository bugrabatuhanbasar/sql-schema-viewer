import Foundation
import SchemaModel
import SQLLexer
import ParserCore

/// MySQL and MariaDB share this target. Which dialect is used is toggled by
/// the `flavor` field; parsers can branch on MariaDB-specific syntax.
public struct MySQLParser: StatementParser {
    public enum Flavor: Sendable { case mysql, mariadb }

    public static var dialect: Dialect { .mysql }
    public let flavor: Flavor

    public init(flavor: Flavor = .mysql) { self.flavor = flavor }

    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        let cfg: LexerConfig = (flavor == .mariadb) ? .mariadb : .mysql
        let buffer = SourceBuffer(source, file: file)
        let splitter = StatementSplitter(config: cfg)
        let slices = splitter.split(buffer)
        var schema = Schema(dialect: flavor == .mariadb ? .mariadb : .mysql)
        schema.stats.skippedStatements = slices.count
        return ParseResult(value: schema)
    }
}
