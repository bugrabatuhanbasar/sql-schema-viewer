import Foundation
import SchemaModel
import SQLLexer
import ParserCore

public struct OracleParser: StatementParser {
    public static var dialect: Dialect { .oracle }
    public init() {}

    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        let buffer = SourceBuffer(source, file: file)
        let index = LineIndex(buffer)
        let splitter = StatementSplitter(config: OracleKeywords.config)
        let slices = splitter.split(buffer)

        var schema = Schema(dialect: .oracle)
        var diagnostics: [Diagnostic] = []
        var pendingIndexes: [Index] = []
        var pendingConstraints: [(Identifier, [Constraint])] = []
        var pendingComments: [(kind: OracleCommentKind, table: Identifier, column: Identifier?, text: String)] = []

        var fully = 0, partial = 0, skipped = 0
        let recognizer = OracleStatementRecognizer(file: file, lineIndex: index)

        for slice in slices {
            switch recognizer.recognize(slice: slice) {
            case .parsedTable(let t):
                schema.tables[t.name] = t
                if t.confidence == .partial { partial += 1 } else { fully += 1 }
            case .parsedIndex(let i): pendingIndexes.append(i); fully += 1
            case .parsedAlterConstraint(let target, let added):
                pendingConstraints.append((target, added)); fully += 1
            case .parsedTableComment(let table, let text):
                pendingComments.append((.table, table, nil, text)); fully += 1
            case .parsedColumnComment(let table, let col, let text):
                pendingComments.append((.column, table, col, text)); fully += 1
            case .parsedView(let v): schema.views[v.name] = v; partial += 1
            case .parsedTrigger(let t): schema.triggers[t.name] = t; partial += 1
            case .parsedRoutine(let r): schema.routines[r.name] = r; partial += 1
            case .skipped(let d): diagnostics.append(d); skipped += 1
            case .ignored: skipped += 1
            }
        }
        for idx in pendingIndexes {
            if var t = schema.tables[idx.table] { t.indexes.append(idx); schema.tables[idx.table] = t }
            else {
                diagnostics.append(Diagnostic(severity: .warning, code: DiagnosticCode.danglingReference, message: "Index references unknown table \(idx.table.raw)", source: idx.source))
            }
        }
        for (target, added) in pendingConstraints {
            if var t = schema.tables[target] { t.constraints.append(contentsOf: added); schema.tables[target] = t }
        }
        for c in pendingComments {
            if var t = schema.tables[c.table] {
                if c.kind == .table { t.comment = c.text }
                else if let colName = c.column,
                        let ci = t.columns.firstIndex(where: { $0.name.normalized == colName.normalized }) {
                    t.columns[ci].comment = c.text
                }
                schema.tables[c.table] = t
            }
        }
        schema.stats = AnalysisStats(fullyParsedObjects: fully, partiallyParsedObjects: partial, skippedStatements: skipped)
        schema.diagnostics = diagnostics
        return ParseResult(value: schema, diagnostics: diagnostics)
    }
}

enum OracleCommentKind { case table, column }

enum OracleStatementOutcome {
    case parsedTable(Table)
    case parsedIndex(Index)
    case parsedAlterConstraint(target: Identifier, added: [Constraint])
    case parsedTableComment(table: Identifier, text: String)
    case parsedColumnComment(table: Identifier, column: Identifier, text: String)
    case parsedView(View)
    case parsedTrigger(Trigger)
    case parsedRoutine(Routine)
    case skipped(Diagnostic)
    case ignored
}

struct OracleStatementRecognizer {
    let file: URL?
    let lineIndex: LineIndex

    func recognize(slice: StatementSlice) -> OracleStatementOutcome {
        var c = TokenCursor(tokens: slice.tokens.filter { !isTrivia($0) }, file: file, lineIndex: lineIndex)
        guard !c.isAtEnd else { return .ignored }
        for kw in ["SELECT", "INSERT", "UPDATE", "DELETE", "MERGE", "GRANT", "REVOKE",
                   "COMMIT", "ROLLBACK", "SAVEPOINT", "SET", "EXEC", "EXECUTE",
                   "BEGIN", "DECLARE", "CALL"] {
            if c.isKeyword(kw) { return .ignored }
        }
        if c.isKeyword("COMMENT") { return parseComment(&c, slice: slice) }
        if c.isKeyword("CREATE") { return parseCreate(&c, slice: slice) }
        if c.isKeyword("ALTER") { return parseAlter(&c, slice: slice) }
        if c.isKeyword("DROP") { return .ignored }
        return .skipped(unsupported("Unrecognized", slice))
    }

    private func parseCreate(_ c: inout TokenCursor, slice: StatementSlice) -> OracleStatementOutcome {
        _ = c.advance()
        _ = c.matchKeyword("OR"); _ = c.matchKeyword("REPLACE")
        _ = c.matchKeyword("GLOBAL") || c.matchKeyword("LOCAL")
        let temporary = c.matchKeyword("TEMPORARY") || c.matchKeyword("TEMP")
        let unique = c.matchKeyword("UNIQUE")
        if c.matchKeyword("TABLE") { return parseTable(&c, slice: slice, temporary: temporary) }
        if c.matchKeyword("INDEX") { return parseIndex(&c, slice: slice, unique: unique) }
        if c.matchKeyword("VIEW") { return parseView(&c, slice: slice, materialized: false) }
        if c.matchKeyword("MATERIALIZED") {
            if c.matchKeyword("VIEW") { return parseView(&c, slice: slice, materialized: true) }
        }
        if c.matchKeyword("TRIGGER") { return parseTrigger(&c, slice: slice) }
        if c.matchKeyword("FUNCTION") { return parseRoutine(&c, slice: slice, kind: .function) }
        if c.matchKeyword("PROCEDURE") { return parseRoutine(&c, slice: slice, kind: .procedure) }
        if c.matchKeyword("PACKAGE") { return parseRoutine(&c, slice: slice, kind: .procedure) }
        if c.matchKeyword("SEQUENCE") || c.matchKeyword("SYNONYM") || c.matchKeyword("TYPE") { return .ignored }
        return .skipped(unsupported("CREATE …", slice))
    }

    private func parseTable(_ c: inout TokenCursor, slice: StatementSlice, temporary: Bool) -> OracleStatementOutcome {
        guard let name = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE TABLE", slice)) }
        guard c.matchPunctuation(0x28) else {
            return .parsedTable(Table(name: name, kind: temporary ? .temporary : .regular, source: sliceRange(slice), confidence: .partial))
        }
        var columns: [Column] = []
        var constraints: [Constraint] = []
        var partial = false
        while !c.isAtEnd && !c.isPunctuation(0x29) {
            let el = parseElement(&c)
            switch el {
            case .column(let col, let inline):
                columns.append(col); constraints.append(contentsOf: inline)
            case .tableConstraint(let cs):
                constraints.append(contentsOf: cs)
            case .partial: partial = true
            }
            if c.matchPunctuation(0x2C) { continue }
            break
        }
        _ = c.matchPunctuation(0x29)
        for col in columns where !col.nullable {
            constraints.append(.notNull(column: col.name, source: col.source))
        }
        return .parsedTable(Table(
            name: name, columns: columns, constraints: constraints,
            kind: temporary ? .temporary : .regular,
            source: sliceRange(slice),
            confidence: partial ? .partial : .complete
        ))
    }

    private enum Element {
        case column(Column, inline: [Constraint])
        case tableConstraint([Constraint])
        case partial
    }

    private func parseElement(_ c: inout TokenCursor) -> Element {
        let start = c.current
        if c.isKeyword("CONSTRAINT") || c.isKeyword("PRIMARY") ||
           c.isKeyword("UNIQUE") || c.isKeyword("FOREIGN") || c.isKeyword("CHECK") {
            return .tableConstraint(parseTableConstraint(&c, startToken: start))
        }
        guard let colName = c.readIdentifier() else { skipElement(&c); return .partial }
        let type = parseType(&c)
        var nullable = true
        var defaultExpr: String? = nil
        var generated: GeneratedKind? = nil
        var inline: [Constraint] = []
        while !c.isAtEnd && !c.isPunctuation(0x2C) && !c.isPunctuation(0x29) {
            if c.matchKeyword("NOT") { if c.matchKeyword("NULL") { nullable = false; continue } }
            if c.matchKeyword("NULL") { nullable = true; continue }
            if c.matchKeyword("DEFAULT") { defaultExpr = readExpression(&c); continue }
            if c.matchKeyword("PRIMARY") {
                _ = c.matchKeyword("KEY")
                inline.append(.primaryKey(columns: [colName], name: nil, source: c.range(from: start)))
                nullable = false; continue
            }
            if c.matchKeyword("UNIQUE") {
                inline.append(.unique(columns: [colName], name: nil, source: c.range(from: start))); continue
            }
            if c.matchKeyword("REFERENCES") {
                if let fk = parseReferencesTail(&c, localColumns: [colName], startToken: start) {
                    inline.append(.foreignKey(fk))
                }
                continue
            }
            if c.matchKeyword("CHECK") {
                let expr = readParenthesized(&c)
                inline.append(.check(expression: expr, name: nil, source: c.range(from: start))); continue
            }
            if c.matchKeyword("GENERATED") {
                _ = c.matchKeyword("ALWAYS") || c.matchKeyword("BY")
                _ = c.matchKeyword("DEFAULT")
                _ = c.matchKeyword("AS")
                if c.matchKeyword("IDENTITY") { generated = .always; continue }
                _ = readParenthesized(&c)
                generated = .stored
                continue
            }
            _ = c.advance()
        }
        return .column(Column(name: colName, type: type, nullable: nullable, defaultExpression: defaultExpr, generated: generated, source: c.range(from: start)), inline: inline)
    }

    private func parseTableConstraint(_ c: inout TokenCursor, startToken: Token) -> [Constraint] {
        var name: Identifier? = nil
        if c.matchKeyword("CONSTRAINT") { name = c.readIdentifier() }
        if c.matchKeyword("PRIMARY") {
            _ = c.matchKeyword("KEY")
            let cols = parseParenColumns(&c)
            return [.primaryKey(columns: cols, name: name, source: c.range(from: startToken))]
        }
        if c.matchKeyword("UNIQUE") {
            let cols = parseParenColumns(&c)
            return [.unique(columns: cols, name: name, source: c.range(from: startToken))]
        }
        if c.matchKeyword("FOREIGN") {
            _ = c.matchKeyword("KEY")
            let cols = parseParenColumns(&c)
            if !c.matchKeyword("REFERENCES") { return [] }
            if let fk = parseReferencesTail(&c, localColumns: cols, name: name, startToken: startToken) {
                return [.foreignKey(fk)]
            }
            return []
        }
        if c.matchKeyword("CHECK") {
            let expr = readParenthesized(&c)
            return [.check(expression: expr, name: name, source: c.range(from: startToken))]
        }
        skipElement(&c); return []
    }

    private func parseReferencesTail(_ c: inout TokenCursor, localColumns: [Identifier], name: Identifier? = nil, startToken: Token) -> ForeignKeySpec? {
        guard let refTable = c.readQualifiedIdentifier() else { return nil }
        var refCols: [Identifier] = []
        if c.isPunctuation(0x28) { refCols = parseParenColumns(&c) }
        var onDelete: ReferentialAction = .noAction
        while c.matchKeyword("ON") {
            if c.matchKeyword("DELETE") { onDelete = readAction(&c) }
            else { break }
        }
        var deferrable = false
        if c.matchKeyword("DEFERRABLE") {
            deferrable = true
            _ = c.matchKeyword("INITIALLY")
            _ = c.matchKeyword("DEFERRED") || c.matchKeyword("IMMEDIATE")
        }
        return ForeignKeySpec(name: name, localColumns: localColumns, referencedTable: refTable, referencedColumns: refCols, onDelete: onDelete, onUpdate: .noAction, deferrable: deferrable, source: c.range(from: startToken))
    }

    private func readAction(_ c: inout TokenCursor) -> ReferentialAction {
        if c.matchKeyword("CASCADE") { return .cascade }
        if c.matchKeyword("SET") { if c.matchKeyword("NULL") { return .setNull } }
        if c.matchKeyword("NO") { _ = c.matchKeyword("ACTION"); return .noAction }
        return .noAction
    }

    private func parseType(_ c: inout TokenCursor) -> DataType {
        var parts: [String] = []
        switch c.current.kind {
        case .identifier: parts.append(c.advance().text)
        case .keyword(let k): parts.append(k); _ = c.advance()
        default: return .unknown(c.current.text)
        }
        // Oracle timestamps: TIMESTAMP WITH LOCAL TIME ZONE
        while c.isKeyword("WITH") || c.isKeyword("WITHOUT") {
            parts.append(c.advance().text)
            if c.isKeyword("LOCAL") { parts.append(c.advance().text) }
            if c.isKeyword("TIME") { parts.append(c.advance().text) }
            if c.isKeyword("ZONE") { parts.append(c.advance().text) }
        }
        var params: [String] = []
        if c.matchPunctuation(0x28) {
            while !c.isAtEnd && !c.isPunctuation(0x29) {
                params.append(c.advance().text)
                if c.isPunctuation(0x2C) { _ = c.advance() }
            }
            _ = c.matchPunctuation(0x29)
        }
        return .named(parts.joined(separator: " "), params: params)
    }

    private func parseAlter(_ c: inout TokenCursor, slice: StatementSlice) -> OracleStatementOutcome {
        _ = c.advance()
        if !c.matchKeyword("TABLE") { return .skipped(unsupported("ALTER …", slice)) }
        guard let target = c.readQualifiedIdentifier() else { return .skipped(unsupported("ALTER TABLE", slice)) }
        var added: [Constraint] = []
        while !c.isAtEnd {
            if c.matchKeyword("ADD") {
                _ = c.matchKeyword("COLUMN")
                if c.isKeyword("CONSTRAINT") || c.isKeyword("PRIMARY") ||
                   c.isKeyword("UNIQUE") || c.isKeyword("FOREIGN") ||
                   c.isKeyword("CHECK") {
                    let start = c.current
                    let cs = parseTableConstraint(&c, startToken: start)
                    added.append(contentsOf: cs)
                }
            } else { _ = c.advance() }
            if c.matchPunctuation(0x2C) { continue }
            break
        }
        if added.isEmpty { return .skipped(unsupported("ALTER TABLE (non-constraint)", slice)) }
        return .parsedAlterConstraint(target: target, added: added)
    }

    private func parseIndex(_ c: inout TokenCursor, slice: StatementSlice, unique: Bool) -> OracleStatementOutcome {
        let name = c.readIdentifier()
        if !c.matchKeyword("ON") { return .skipped(unsupported("CREATE INDEX", slice)) }
        guard let table = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE INDEX", slice)) }
        let cols = parseParenColumns(&c).map { IndexColumn(column: $0) }
        return .parsedIndex(Index(name: name, table: table, columns: cols, unique: unique, source: sliceRange(slice)))
    }

    private func parseComment(_ c: inout TokenCursor, slice: StatementSlice) -> OracleStatementOutcome {
        _ = c.advance() // COMMENT
        _ = c.matchKeyword("ON")
        if c.matchKeyword("TABLE") {
            guard let table = c.readQualifiedIdentifier() else { return .skipped(unsupported("COMMENT", slice)) }
            _ = c.matchKeyword("IS")
            let text = extractStringLiteral(&c) ?? ""
            return .parsedTableComment(table: table, text: text)
        }
        if c.matchKeyword("COLUMN") {
            guard let q = c.readQualifiedIdentifier(), let table = q.schema else { return .skipped(unsupported("COMMENT COLUMN", slice)) }
            _ = c.matchKeyword("IS")
            let text = extractStringLiteral(&c) ?? ""
            return .parsedColumnComment(table: Identifier(raw: table), column: Identifier(raw: q.raw), text: text)
        }
        return .skipped(unsupported("COMMENT", slice))
    }

    private func extractStringLiteral(_ c: inout TokenCursor) -> String? {
        if case .stringLiteral = c.current.kind {
            var raw = c.advance().text
            if raw.hasPrefix("'") && raw.hasSuffix("'") {
                raw = String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            return raw
        }
        return nil
    }

    private func parseView(_ c: inout TokenCursor, slice: StatementSlice, materialized: Bool) -> OracleStatementOutcome {
        guard let name = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE VIEW", slice)) }
        return .parsedView(View(name: name, materialized: materialized, definitionSQL: slice.text, source: sliceRange(slice), confidence: .partial))
    }

    private func parseTrigger(_ c: inout TokenCursor, slice: StatementSlice) -> OracleStatementOutcome {
        guard let name = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE TRIGGER", slice)) }
        var timing: TriggerTiming = .unknown
        if c.matchKeyword("BEFORE") { timing = .before }
        else if c.matchKeyword("AFTER") { timing = .after }
        else if c.matchKeywords(["INSTEAD", "OF"]) { timing = .insteadOf }
        var events: [TriggerEvent] = []
        while true {
            if c.matchKeyword("INSERT") { events.append(.insert) }
            else if c.matchKeyword("UPDATE") { events.append(.update) }
            else if c.matchKeyword("DELETE") { events.append(.delete) }
            else { break }
            if !c.matchKeyword("OR") { break }
        }
        var table: Identifier = Identifier(raw: "")
        if c.matchKeyword("ON") { table = c.readQualifiedIdentifier() ?? table }
        return .parsedTrigger(Trigger(name: name, table: table, timing: timing, events: events, bodySQL: slice.text, source: sliceRange(slice), confidence: .partial))
    }

    private func parseRoutine(_ c: inout TokenCursor, slice: StatementSlice, kind: RoutineKind) -> OracleStatementOutcome {
        guard let name = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE ROUTINE", slice)) }
        return .parsedRoutine(Routine(name: name, kind: kind, bodySQL: slice.text, source: sliceRange(slice), confidence: .partial))
    }

    // helpers
    private func parseParenColumns(_ c: inout TokenCursor) -> [Identifier] {
        var out: [Identifier] = []
        guard c.matchPunctuation(0x28) else { return out }
        while !c.isAtEnd && !c.isPunctuation(0x29) {
            if let id = c.readIdentifier() { out.append(id) }
            while !c.isPunctuation(0x2C) && !c.isPunctuation(0x29) && !c.isAtEnd { _ = c.advance() }
            if c.isPunctuation(0x2C) { _ = c.advance() }
        }
        _ = c.matchPunctuation(0x29)
        return out
    }
    private func readParenthesized(_ c: inout TokenCursor) -> String {
        guard c.matchPunctuation(0x28) else { return "" }
        var depth = 1; var parts: [String] = []
        while !c.isAtEnd && depth > 0 {
            let tk = c.current
            if case .punctuation(let b) = tk.kind {
                if b == 0x28 { depth += 1 }
                else if b == 0x29 { depth -= 1; if depth == 0 { _ = c.advance(); break } }
            }
            parts.append(tk.text); _ = c.advance()
        }
        return parts.joined(separator: " ")
    }
    private func readExpression(_ c: inout TokenCursor) -> String {
        var depth = 0; var parts: [String] = []
        while !c.isAtEnd {
            let tk = c.current
            if case .punctuation(let b) = tk.kind {
                if b == 0x28 { depth += 1 }
                else if b == 0x29 { if depth == 0 { break }; depth -= 1 }
                else if depth == 0 && (b == 0x2C || b == 0x3B) { break }
            }
            if depth == 0, case .keyword(let k) = tk.kind {
                let stops: Set<String> = ["NOT", "NULL", "DEFAULT", "PRIMARY", "UNIQUE", "REFERENCES", "CHECK", "GENERATED", "CONSTRAINT"]
                if stops.contains(k) { break }
            }
            parts.append(tk.text); _ = c.advance()
        }
        return parts.joined(separator: " ")
    }
    private func skipElement(_ c: inout TokenCursor) {
        var depth = 0
        while !c.isAtEnd {
            if case .punctuation(let b) = c.current.kind {
                if b == 0x28 { depth += 1 }
                else if b == 0x29 { if depth == 0 { return }; depth -= 1 }
                else if depth == 0 && b == 0x2C { return }
            }
            _ = c.advance()
        }
    }
    private func sliceRange(_ slice: StatementSlice) -> SourceRange {
        let s = lineIndex.position(atByteOffset: slice.byteOffset)
        let e = lineIndex.position(atByteOffset: slice.byteOffset + slice.byteLength)
        return SourceRange(file: file, startLine: s.line, startColumn: s.column, endLine: e.line, endColumn: e.column, byteOffset: slice.byteOffset, byteLength: slice.byteLength)
    }
    private func unsupported(_ what: String, _ slice: StatementSlice) -> Diagnostic {
        Diagnostic(severity: .info, code: DiagnosticCode.unsupportedFeature, message: "Skipped: \(what)", source: sliceRange(slice))
    }
    private func isTrivia(_ t: Token) -> Bool { if case .whitespace = t.kind { return true }; if case .lineComment = t.kind { return true }; if case .blockComment = t.kind { return true }; return false }
}
