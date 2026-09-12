import Foundation
import SchemaModel

/// Mermaid ER diagram exporter. Full formatting arrives in M10; this stub
/// already emits a valid, if bare, diagram.
public enum MermaidExporter {
    public static func export(_ schema: Schema) -> String {
        var lines: [String] = ["erDiagram"]
        let tables = schema.tables.values.sorted { $0.name.normalized < $1.name.normalized }
        for t in tables {
            lines.append("  \(t.name.raw) {")
            for c in t.columns {
                lines.append("    \(c.type.displayName) \(c.name.raw)")
            }
            lines.append("  }")
        }
        for t in tables {
            for fk in t.foreignKeys {
                lines.append("  \(t.name.raw) }o--|| \(fk.referencedTable.raw) : \"\(fk.name?.raw ?? "fk")\"")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
