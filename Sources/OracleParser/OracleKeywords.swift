import Foundation
import SQLLexer

enum OracleKeywords {
    static let all: Set<String> = LexerConfig.commonKeywords.union([
        "BINARY_DOUBLE", "BINARY_FLOAT", "BLOB", "BODY", "BY", "CACHE",
        "CASCADE", "CHAR", "CLOB", "COMPRESS", "CONSTRAINTS", "DATE",
        "DEFERRABLE", "DEFERRED", "DISABLE", "DISTINCT", "DOMAIN", "ENABLE",
        "EXCEPTION", "GENERATED", "GLOBAL", "GRANT", "IDENTITY", "IN",
        "INITIALLY", "IS", "LOCAL", "LONG", "MATCH", "MAXVALUE", "MINVALUE",
        "NO", "NOCACHE", "NOCOMPRESS", "NOCYCLE", "NOMAXVALUE", "NOMINVALUE",
        "NOORDER", "NOWAIT", "NUMBER", "NVARCHAR2", "PACKAGE", "PARTITION",
        "PARALLEL", "PCTFREE", "PLS_INTEGER", "PRAGMA", "RAW", "RESTRICT",
        "REVOKE", "ROW", "ROWID", "SEQUENCE", "SET", "START", "STORAGE",
        "SUBTYPE", "SYNONYM", "SYSDATE", "SYSTEM", "SYSTIMESTAMP",
        "TABLESPACE", "TEMPORARY", "TIMESTAMP", "TYPE", "UROWID",
        "VARCHAR2", "VARYING", "XMLTYPE",
    ])

    static let config = LexerConfig(
        dialect: .oracle,
        identifierQuote: 0x22,
        alternateIdentifierQuote: nil,
        supportsDollarQuoting: false,
        supportsHashComments: false,
        keywords: all
    )
}
