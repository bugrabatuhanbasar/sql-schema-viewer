import Foundation
import SchemaModel

/// Basic V1 schema-quality checks. Full implementation lands in M9.
public enum QualityChecks {
    public static func run(on schema: Schema) -> [Diagnostic] {
        var out: [Diagnostic] = []
        for (_, table) in schema.tables {
            if table.primaryKeyColumns.isEmpty {
                out.append(Diagnostic(
                    severity: .warning,
                    code: "W0010",
                    message: "Table \(table.name.raw) has no primary key",
                    source: table.source
                ))
            }
        }
        return out
    }
}
