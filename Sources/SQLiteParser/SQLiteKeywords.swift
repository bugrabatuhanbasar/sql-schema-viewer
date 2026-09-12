import Foundation
import SQLLexer

enum SQLiteKeywords {
    static let all: Set<String> = LexerConfig.commonKeywords.union([
        "ABORT", "AUTOINCREMENT", "CASCADE", "COLLATE", "CONFLICT",
        "DEFERRED", "DELETE", "FAIL", "GENERATED", "IF", "IGNORE",
        "INITIALLY", "INTEGER", "MATCH", "NO", "NULLS", "PARTIAL",
        "REPLACE", "RESTRICT", "SIMPLE", "STORED", "TEXT", "VIRTUAL",
        "WITHOUT", "ROWID",
    ])

    static let config = LexerConfig(
        dialect: .sqlite,
        identifierQuote: 0x22,
        alternateIdentifierQuote: 0x60,
        supportsDollarQuoting: false,
        supportsHashComments: false,
        keywords: all
    )
}
