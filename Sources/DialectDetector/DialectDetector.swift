import Foundation
import SchemaModel

/// Heuristic dialect detection. Order matters: check the most distinctive
/// tokens first. When ambiguous, returns `.unknown` so the caller can prompt
/// the user to override.
public enum DialectDetector {
    public static func detect(fromContents text: String, filename: String? = nil) -> Dialect {
        if let filename, filename.lowercased().hasSuffix(".dbml") { return .dbml }

        let head = text.prefix(8192)
        let upper = head.uppercased()

        // DBML markers
        if upper.contains("TABLE ") && (upper.contains("REF:") || upper.contains("[REF:")) {
            return .dbml
        }
        // Oracle-specific
        if upper.contains("CREATE OR REPLACE PACKAGE")
            || upper.contains("NUMBER(")
            || upper.contains("VARCHAR2(")
            || upper.contains("PRAGMA ") {
            return .oracle
        }
        // PostgreSQL
        if upper.contains("::")
            || upper.contains("SERIAL")
            || upper.contains("RETURNS TABLE")
            || upper.contains("$$")
            || upper.contains("CREATE MATERIALIZED VIEW") {
            return .postgres
        }
        // MySQL / MariaDB
        if head.contains("`") || upper.contains("ENGINE=") || upper.contains("AUTO_INCREMENT") {
            if upper.contains("VIRTUAL") && upper.contains("PERSISTENT") { return .mariadb }
            return .mysql
        }
        // SQLite
        if upper.contains("AUTOINCREMENT") || upper.contains("PRAGMA ") || upper.contains("WITHOUT ROWID") {
            return .sqlite
        }
        return .unknown
    }
}
