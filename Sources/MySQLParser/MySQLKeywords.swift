import Foundation
import SQLLexer

enum MySQLKeywords {
    static let all: Set<String> = LexerConfig.commonKeywords.union([
        "ADD", "AUTO_INCREMENT", "BIGINT", "BINARY", "BTREE", "CASCADE",
        "CHARACTER", "CHARSET", "COLLATE", "COLLATION", "COLUMN",
        "CURRENT_TIMESTAMP", "DELETE", "DELIMITER", "DOUBLE", "ENGINE",
        "EXTRACT", "FIRST", "FULL", "FULLTEXT", "GENERATED", "GLOBAL",
        "HASH", "IDENTITY", "IN", "INT", "INTEGER", "INVISIBLE", "IS",
        "JSON", "KEYS", "LOCAL", "MEDIUMINT", "MODIFIES", "NO", "NULLS",
        "PARTITION", "RESTRICT", "ROW", "ROW_FORMAT", "SET", "SHOW",
        "SPATIAL", "STORAGE", "STORED", "STRICT", "TABLESPACE", "TINYINT",
        "UNSIGNED", "VARBINARY", "VIRTUAL", "VISIBLE", "ZEROFILL",
    ])

    static let mysqlConfig = LexerConfig(
        dialect: .mysql,
        identifierQuote: 0x22,
        alternateIdentifierQuote: 0x60,
        supportsDollarQuoting: false,
        supportsHashComments: true,
        keywords: all
    )

    static let mariadbConfig = LexerConfig(
        dialect: .mariadb,
        identifierQuote: 0x22,
        alternateIdentifierQuote: 0x60,
        supportsDollarQuoting: false,
        supportsHashComments: true,
        keywords: all
    )
}
