import Foundation
import SchemaModel
import ParserCore

/// DBML (dbml-lang.org) parser + serializer. Covers the constructs V1
/// needs — `Table`, columns with `[pk, unique, not null, increment,
/// default: …, note: '…', ref: > other.col]`, top-level `Ref:` lines,
/// enums (registered as no-op types), and comments. Anything unrecognized
/// is emitted as an `.info` diagnostic and skipped.
public struct DBMLParser: StatementParser {
    public static var dialect: Dialect { .dbml }
    public init() {}

    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        var lex = DBMLLexer(source: source)
        var schema = Schema(dialect: .dbml)
        var diagnostics: [Diagnostic] = []
        var fully = 0, partial = 0, skipped = 0

        while !lex.isAtEnd {
            lex.skipTrivia()
            if lex.isAtEnd { break }
            let start = lex.location
            guard let keyword = lex.peekWord() else { lex.advance(); continue }

            let lowered = keyword.lowercased()
            switch lowered {
            case "table":
                _ = lex.readWord()
                if let table = parseTable(lex: &lex, file: file, startLine: start.line, diagnostics: &diagnostics) {
                    schema.tables[table.name] = table
                    if table.confidence == .complete { fully += 1 } else { partial += 1 }
                } else {
                    skipped += 1
                }
            case "ref":
                _ = lex.readWord()
                if lex.consume(":") {
                    if let ref = parseInlineRef(lex: &lex, startLine: start.line) {
                        attachForeignKey(&schema, ref: ref)
                        fully += 1
                    } else { skipped += 1 }
                } else {
                    // Named ref block: `Ref name { … }` — skip
                    skipBlock(lex: &lex); skipped += 1
                }
            case "enum", "tablegroup", "project", "note":
                _ = lex.readWord()
                _ = lex.readWord() // optional name
                skipBlock(lex: &lex)
                diagnostics.append(Diagnostic(
                    severity: .info, code: DiagnosticCode.skippedStatement,
                    message: "DBML \(lowered) blocks are ignored in V1",
                    source: sourceRange(file: file, line: start.line)
                ))
                skipped += 1
            default:
                lex.advance()
            }
        }

        schema.stats = AnalysisStats(fullyParsedObjects: fully, partiallyParsedObjects: partial, skippedStatements: skipped)
        schema.diagnostics = diagnostics
        return ParseResult(value: schema, diagnostics: diagnostics)
    }

    // MARK: table

    private func parseTable(lex: inout DBMLLexer, file: URL?, startLine: Int, diagnostics: inout [Diagnostic]) -> Table? {
        lex.skipTrivia()
        guard let name = lex.readWord() else { return nil }
        var tableName = Identifier(raw: name)
        // Optional `as alias`
        lex.skipTrivia()
        if lex.peekWord()?.lowercased() == "as" {
            _ = lex.readWord()
            _ = lex.readWord()
        }
        // Optional table-level [note: '...']
        lex.skipTrivia()
        _ = lex.skipBracketedSettings()
        lex.skipTrivia()
        guard lex.consume("{") else { return nil }
        var columns: [Column] = []
        var constraints: [Constraint] = []
        var pendingRefs: [(Identifier, Identifier, Identifier)] = [] // (local, refTable, refCol)
        while !lex.isAtEnd {
            lex.skipTrivia()
            if lex.consume("}") { break }
            if lex.peekWord()?.lowercased() == "note" {
                _ = lex.readWord()
                _ = lex.consume(":")
                lex.skipTrivia()
                _ = lex.readString()
                continue
            }
            if lex.peekWord()?.lowercased() == "indexes" {
                _ = lex.readWord()
                skipBlock(lex: &lex)
                continue
            }
            guard let colName = lex.readWord() else { lex.advance(); continue }
            lex.skipTrivia()
            let typeName = lex.readWord() ?? "unknown"
            var typeParams: [String] = []
            lex.skipTrivia()
            if lex.consume("(") {
                var parts: [String] = []
                while !lex.isAtEnd && !lex.check(")") { parts.append(lex.readAtom()); lex.skipTrivia(); _ = lex.consume(",") }
                _ = lex.consume(")")
                typeParams = parts
            }
            var nullable = true
            var defaultExpr: String? = nil
            var isPk = false
            var isUnique = false
            var refTarget: (Identifier, Identifier)? = nil
            lex.skipTrivia()
            if lex.consume("[") {
                while !lex.isAtEnd && !lex.check("]") {
                    lex.skipTrivia()
                    guard let opt = lex.readWord() else { lex.advance(); continue }
                    let lower = opt.lowercased()
                    switch lower {
                    case "pk", "primary": isPk = true; nullable = false
                    case "unique": isUnique = true
                    case "increment": break
                    case "not":
                        // `not null`
                        lex.skipTrivia()
                        if lex.peekWord()?.lowercased() == "null" { _ = lex.readWord(); nullable = false }
                    case "null": nullable = true
                    case "default":
                        lex.skipTrivia(); _ = lex.consume(":"); lex.skipTrivia()
                        defaultExpr = lex.readString() ?? lex.readAtom()
                    case "note":
                        lex.skipTrivia(); _ = lex.consume(":"); lex.skipTrivia()
                        _ = lex.readString()
                    case "ref":
                        lex.skipTrivia(); _ = lex.consume(":"); lex.skipTrivia()
                        // relationship glyph: > < - <>
                        _ = lex.consume(">") || lex.consume("<") || lex.consume("-")
                        lex.skipTrivia()
                        if let ref = lex.readQualifiedWord() { refTarget = ref }
                    default: break
                    }
                    lex.skipTrivia()
                    if !lex.consume(",") { break }
                }
                _ = lex.consume("]")
            }

            let column = Column(
                name: Identifier(raw: colName),
                type: .named(typeName, params: typeParams),
                nullable: nullable,
                defaultExpression: defaultExpr,
                source: sourceRange(file: file, line: lex.location.line)
            )
            columns.append(column)
            if isPk {
                constraints.append(.primaryKey(columns: [column.name], name: nil, source: column.source))
            }
            if isUnique {
                constraints.append(.unique(columns: [column.name], name: nil, source: column.source))
            }
            if let ref = refTarget {
                pendingRefs.append((column.name, ref.0, ref.1))
            }
        }
        for col in columns where !col.nullable {
            constraints.append(.notNull(column: col.name, source: col.source))
        }
        for (local, refT, refC) in pendingRefs {
            constraints.append(.foreignKey(ForeignKeySpec(
                localColumns: [local],
                referencedTable: refT,
                referencedColumns: [refC]
            )))
        }
        return Table(
            name: tableName, columns: columns, constraints: constraints,
            source: sourceRange(file: file, line: startLine),
            confidence: .complete
        )
    }

    private struct InlineRef {
        var left: (table: Identifier, column: Identifier)
        var right: (table: Identifier, column: Identifier)
        var glyph: String // "<", ">", "-", "<>"
    }

    private func parseInlineRef(lex: inout DBMLLexer, startLine: Int) -> InlineRef? {
        lex.skipTrivia()
        guard let l = lex.readQualifiedWord() else { return nil }
        lex.skipTrivia()
        var glyph = ">"
        if lex.consume(">") { glyph = ">" }
        else if lex.consume("<") { if lex.consume(">") { glyph = "<>" } else { glyph = "<" } }
        else if lex.consume("-") { glyph = "-" }
        lex.skipTrivia()
        guard let r = lex.readQualifiedWord() else { return nil }
        return InlineRef(left: l, right: r, glyph: glyph)
    }

    private func attachForeignKey(_ schema: inout Schema, ref: InlineRef) {
        // For > (many-to-one) FK belongs on left; for < FK on right; for -
        // treat as left-owning by convention.
        let ownerName: Identifier
        let ownerColumn: Identifier
        let refTable: Identifier
        let refColumn: Identifier
        switch ref.glyph {
        case "<":
            ownerName = ref.right.table; ownerColumn = ref.right.column
            refTable = ref.left.table; refColumn = ref.left.column
        default:
            ownerName = ref.left.table; ownerColumn = ref.left.column
            refTable = ref.right.table; refColumn = ref.right.column
        }
        if var t = schema.tables[ownerName] {
            t.constraints.append(.foreignKey(ForeignKeySpec(
                localColumns: [ownerColumn],
                referencedTable: refTable,
                referencedColumns: [refColumn]
            )))
            schema.tables[ownerName] = t
        }
    }

    private func skipBlock(lex: inout DBMLLexer) {
        lex.skipTrivia()
        if !lex.consume("{") { return }
        var depth = 1
        while !lex.isAtEnd && depth > 0 {
            if lex.consume("{") { depth += 1 }
            else if lex.consume("}") { depth -= 1 }
            else { lex.advance() }
        }
    }

    private func sourceRange(file: URL?, line: Int) -> SourceRange {
        SourceRange(file: file, startLine: line, startColumn: 1, endLine: line, endColumn: 1, byteOffset: 0, byteLength: 0)
    }
}

/// Emit DBML text from a `Schema`. Reports lossy transformations via
/// `.info` diagnostics on the returned `ParseResult`.
public enum DBMLExporter {
    public static func export(_ schema: Schema) -> ParseResult<String> {
        var out: [String] = []
        var diags: [Diagnostic] = []
        out.append("// Generated by Mac SQL Schema Viewer\n")
        let tables = schema.tables.values.sorted { $0.name.normalized < $1.name.normalized }
        for t in tables {
            out.append("Table \(t.name.raw) {")
            for c in t.columns {
                var attrs: [String] = []
                if t.primaryKeyColumns.contains(c.name) { attrs.append("pk") }
                if !c.nullable { attrs.append("not null") }
                if let def = c.defaultExpression { attrs.append("default: `\(def)`") }
                let attrClause = attrs.isEmpty ? "" : " [\(attrs.joined(separator: ", "))]"
                out.append("  \(c.name.raw) \(c.type.displayName)\(attrClause)")
            }
            if let comment = t.comment {
                out.append("  Note: '\(comment.replacingOccurrences(of: "'", with: "\\'"))'")
            }
            out.append("}")
            out.append("")
            if !t.indexes.isEmpty {
                diags.append(Diagnostic(
                    severity: .info, code: DiagnosticCode.dbmlLossyExport,
                    message: "Index details on \(t.name.raw) simplified in DBML export",
                    source: t.source
                ))
            }
        }
        for t in tables {
            for fk in t.foreignKeys {
                guard let localCol = fk.localColumns.first,
                      let refCol = fk.referencedColumns.first else { continue }
                out.append("Ref: \(t.name.raw).\(localCol.raw) > \(fk.referencedTable.raw).\(refCol.raw)")
            }
        }
        return ParseResult(value: out.joined(separator: "\n") + "\n", diagnostics: diags)
    }
}
