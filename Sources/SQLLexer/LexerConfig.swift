import Foundation
import SchemaModel

/// Dialect-specific tokenization knobs. Kept minimal for M1; the recognizers
/// per dialect will override as needed.
public struct LexerConfig: Sendable {
    public var dialect: Dialect
    public var identifierQuote: UInt8          // typically '"'
    public var alternateIdentifierQuote: UInt8? // '`' (MySQL), '[' handled specially (SQL Server, future)
    public var supportsDollarQuoting: Bool     // Postgres
    public var supportsDoubleDashComments: Bool // all supported dialects
    public var supportsHashComments: Bool      // MySQL/MariaDB
    public var keywords: Set<String>           // uppercased

    public init(
        dialect: Dialect,
        identifierQuote: UInt8 = 0x22,
        alternateIdentifierQuote: UInt8? = nil,
        supportsDollarQuoting: Bool = false,
        supportsDoubleDashComments: Bool = true,
        supportsHashComments: Bool = false,
        keywords: Set<String> = LexerConfig.commonKeywords
    ) {
        self.dialect = dialect
        self.identifierQuote = identifierQuote
        self.alternateIdentifierQuote = alternateIdentifierQuote
        self.supportsDollarQuoting = supportsDollarQuoting
        self.supportsDoubleDashComments = supportsDoubleDashComments
        self.supportsHashComments = supportsHashComments
        self.keywords = keywords
    }

    /// A conservative shared keyword set covering DDL statements the
    /// splitter needs to know about. Individual parsers will use their own
    /// richer sets.
    public static let commonKeywords: Set<String> = [
        "CREATE", "ALTER", "DROP", "TABLE", "VIEW", "MATERIALIZED",
        "INDEX", "UNIQUE", "PRIMARY", "FOREIGN", "KEY", "REFERENCES",
        "CONSTRAINT", "CHECK", "NOT", "NULL", "DEFAULT",
        "TRIGGER", "FUNCTION", "PROCEDURE", "RETURNS", "LANGUAGE",
        "BEGIN", "END", "AS", "IF", "OR", "REPLACE", "EXISTS",
        "COMMENT", "ON", "TO", "SELECT", "FROM", "JOIN", "WHERE",
        "SCHEMA", "USING", "WITH", "TEMP", "TEMPORARY", "UNLOGGED",
        "INSERT", "UPDATE", "DELETE", "TRUNCATE", "BEFORE", "AFTER",
        "INSTEAD", "OF", "FOR", "EACH", "ROW", "STATEMENT",
        "ADD", "COLUMN", "CASCADE", "RESTRICT", "ACTION", "IS", "SET",
    ]

    public static let postgres = LexerConfig(
        dialect: .postgres,
        identifierQuote: 0x22,
        alternateIdentifierQuote: nil,
        supportsDollarQuoting: true,
        supportsHashComments: false
    )

    public static let mysql = LexerConfig(
        dialect: .mysql,
        identifierQuote: 0x22,
        alternateIdentifierQuote: 0x60,
        supportsDollarQuoting: false,
        supportsHashComments: true
    )

    public static let mariadb = LexerConfig(
        dialect: .mariadb,
        identifierQuote: 0x22,
        alternateIdentifierQuote: 0x60,
        supportsDollarQuoting: false,
        supportsHashComments: true
    )

    public static let sqlite = LexerConfig(
        dialect: .sqlite,
        identifierQuote: 0x22,
        alternateIdentifierQuote: 0x60,
        supportsDollarQuoting: false,
        supportsHashComments: false
    )

    public static let oracle = LexerConfig(
        dialect: .oracle,
        identifierQuote: 0x22,
        alternateIdentifierQuote: nil,
        supportsDollarQuoting: false,
        supportsHashComments: false
    )
}
