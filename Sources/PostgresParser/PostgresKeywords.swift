import Foundation
import SQLLexer

enum PostgresKeywords {
    static let all: Set<String> = LexerConfig.commonKeywords.union([
        "ADD", "ALWAYS", "ARRAY", "BY", "CASCADE", "CLUSTER", "COLLATE",
        "COLUMN", "CONCURRENTLY", "DEFERRABLE", "DEFERRED", "DELETE",
        "DISTINCT", "DO", "DOMAIN", "ENABLE", "EXCLUDE", "GENERATED",
        "GLOBAL", "GRANT", "IDENTITY", "IMMEDIATE", "IN", "INCLUDE",
        "INHERITS", "INITIALLY", "IS", "LOCAL", "MATCH", "NO", "NOTHING",
        "NULLS", "OWNED", "PARTITION", "RESTRICT", "REVOKE", "ROW",
        "SEQUENCE", "SET", "STORED", "TABLESPACE", "THEN", "TRIGGER",
        "TYPE", "USER", "VALUES", "WITHOUT",
    ])

    static let postgresConfig: SQLLexer.LexerConfig = LexerConfig(
        dialect: .postgres,
        identifierQuote: 0x22,
        alternateIdentifierQuote: nil,
        supportsDollarQuoting: true,
        supportsHashComments: false,
        keywords: all
    )
}
