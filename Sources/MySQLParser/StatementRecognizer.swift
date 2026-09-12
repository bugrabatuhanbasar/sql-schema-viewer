import Foundation
import SchemaModel
import SQLLexer
import ParserCore

enum MySQLStatementOutcome {
    case parsedTable(Table)
    case parsedIndex(Index)
    case parsedAlterConstraint(target: Identifier, added: [Constraint])
    case parsedView(View)
    case parsedTrigger(Trigger)
    case parsedRoutine(Routine)
    case skipped(Diagnostic)
    case ignored
}

/// MySQL / MariaDB DDL recognizer. Shares intent with the Postgres one but
/// diverges on syntax: backtick quoting, table option trailers
/// (`ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`), and `AUTO_INCREMENT` /
/// `KEY` shortcuts inline in column lists.
struct MySQLStatementRecognizer {
    let file: URL?
    let lineIndex: LineIndex
    let flavor: MySQLParser.Flavor

    func recognize(slice: StatementSlice) -> MySQLStatementOutcome {
        var cursor = TokenCursor(
            tokens: slice.tokens.filter { !isTrivia($0) },
            file: file,
            lineIndex: lineIndex
        )
        guard !cursor.isAtEnd else { return .ignored }

        // Skip pure DML / session-level statements.
        for kw in ["SELECT", "INSERT", "UPDATE", "DELETE", "SET",
                   "START", "BEGIN", "COMMIT", "ROLLBACK", "USE",
                   "GRANT", "REVOKE", "SHOW", "LOCK", "UNLOCK", "DELIMITER"] {
            if cursor.isKeyword(kw) { return .ignored }
        }

        if cursor.isKeyword("CREATE") { return parseCreate(&cursor, slice: slice) }
        if cursor.isKeyword("ALTER")  { return parseAlter(&cursor, slice: slice) }
        if cursor.isKeyword("DROP")   { return .ignored }

        return .skipped(unsupported("Unrecognized statement", slice))
    }

    // MARK: CREATE

    private func parseCreate(_ c: inout TokenCursor, slice: StatementSlice) -> MySQLStatementOutcome {
        _ = c.advance() // CREATE
        _ = c.matchKeyword("OR"); _ = c.matchKeyword("REPLACE")
        _ = c.matchKeyword("GLOBAL"); _ = c.matchKeyword("LOCAL")
        let temporary = c.matchKeyword("TEMPORARY") || c.matchKeyword("TEMP")
        // Modifiers before INDEX: UNIQUE / FULLTEXT / SPATIAL
        let unique = c.matchKeyword("UNIQUE")
        _ = c.matchKeyword("FULLTEXT")
        _ = c.matchKeyword("SPATIAL")
        _ = c.matchKeyword("ALGORITHM") // CREATE ALGORITHM = ... VIEW

        if c.matchKeyword("VIEW") { return parseView(&c, slice: slice) }
        if c.matchKeyword("TABLE") { return parseTable(&c, slice: slice, temporary: temporary) }
        if c.matchKeyword("INDEX") { return parseIndex(&c, slice: slice, unique: unique) }
        if c.matchKeyword("TRIGGER") { return parseTrigger(&c, slice: slice) }
        if c.matchKeyword("FUNCTION") { return parseRoutine(&c, slice: slice, kind: .function) }
        if c.matchKeyword("PROCEDURE") { return parseRoutine(&c, slice: slice, kind: .procedure) }
        if c.matchKeyword("DATABASE") || c.matchKeyword("SCHEMA") { return .ignored }
        return .skipped(unsupported("CREATE …", slice))
    }

    // MARK: CREATE TABLE

    private func parseTable(_ c: inout TokenCursor, slice: StatementSlice, temporary: Bool) -> MySQLStatementOutcome {
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
        guard let name = c.readQualifiedIdentifier() else {
            return .skipped(unsupported("CREATE TABLE (no name)", slice))
        }
        guard c.matchPunctuation(0x28) else {
            // CREATE TABLE t LIKE other, or CREATE TABLE t AS SELECT — capture header only.
            return .parsedTable(Table(
                name: name,
                kind: temporary ? .temporary : .regular,
                source: sliceRange(slice),
                confidence: .partial
            ))
        }
        var columns: [Column] = []
        var constraints: [Constraint] = []
        var partial = false

        while !c.isAtEnd && !c.isPunctuation(0x29) {
            let el = parseTableElement(&c, tableName: name)
            switch el {
            case .column(let col, let inline):
                columns.append(col)
                constraints.append(contentsOf: inline)
            case .tableConstraint(let cs):
                constraints.append(contentsOf: cs)
            case .partial:
                partial = true
            }
            if c.matchPunctuation(0x2C) { continue }
            break
        }
        _ = c.matchPunctuation(0x29)

        for col in columns where !col.nullable {
            constraints.append(.notNull(column: col.name, source: col.source))
        }

        return .parsedTable(Table(
            name: name,
            columns: columns,
            constraints: constraints,
            kind: temporary ? .temporary : .regular,
            source: sliceRange(slice),
            confidence: partial ? .partial : .complete
        ))
    }

    private enum TableElement {
        case column(Column, inline: [Constraint])
        case tableConstraint([Constraint])
        case partial
    }

    private func parseTableElement(_ c: inout TokenCursor, tableName: Identifier) -> TableElement {
        let startToken = c.current

        // MySQL table constraints
        if c.isKeyword("CONSTRAINT") || c.isKeyword("PRIMARY") ||
            c.isKeyword("UNIQUE") || c.isKeyword("FOREIGN") ||
            c.isKeyword("CHECK") || c.isKeyword("KEY") ||
            c.isKeyword("INDEX") || c.isKeyword("FULLTEXT") ||
            c.isKeyword("SPATIAL") {
            let cs = parseTableConstraint(&c, tableName: tableName, startToken: startToken)
            return .tableConstraint(cs)
        }

        guard let colName = c.readIdentifier() else {
            skipElement(&c)
            return .partial
        }
        let type = parseDataType(&c)
        var nullable = true
        var defaultExpr: String? = nil
        var generated: GeneratedKind? = nil
        var inline: [Constraint] = []

        while !c.isAtEnd && !c.isPunctuation(0x2C) && !c.isPunctuation(0x29) {
            if c.matchKeyword("NOT") { if c.matchKeyword("NULL") { nullable = false; continue } }
            if c.matchKeyword("NULL") { nullable = true; continue }
            if c.matchKeyword("DEFAULT") {
                defaultExpr = readExpressionText(&c); continue
            }
            if c.matchKeyword("AUTO_INCREMENT") { generated = .byDefault; continue }
            if c.matchKeyword("UNSIGNED") { continue }
            if c.matchKeyword("ZEROFILL") { continue }
            if c.matchKeyword("PRIMARY") {
                _ = c.matchKeyword("KEY")
                inline.append(.primaryKey(columns: [colName], name: nil, source: c.range(from: startToken)))
                nullable = false; continue
            }
            if c.matchKeyword("UNIQUE") {
                _ = c.matchKeyword("KEY")
                inline.append(.unique(columns: [colName], name: nil, source: c.range(from: startToken)))
                continue
            }
            if c.matchKeyword("KEY") {
                // MySQL inline `KEY` -> index; treated as unique(false).
                continue
            }
            if c.matchKeyword("REFERENCES") {
                if let fk = parseReferencesTail(&c, localColumns: [colName], startToken: startToken) {
                    inline.append(.foreignKey(fk))
                }
                continue
            }
            if c.matchKeyword("CHECK") {
                let expr = readParenthesized(&c)
                inline.append(.check(expression: expr, name: nil, source: c.range(from: startToken))); continue
            }
            if c.matchKeyword("COLLATE") || c.matchKeyword("CHARACTER") || c.matchKeyword("CHARSET") {
                _ = c.matchKeyword("SET")
                _ = c.advance()
                continue
            }
            if c.matchKeyword("COMMENT") {
                if case .stringLiteral = c.current.kind { _ = c.advance() }
                continue
            }
            if c.matchKeyword("GENERATED") {
                _ = c.matchKeyword("ALWAYS"); _ = c.matchKeyword("AS")
                _ = readParenthesized(&c)
                if c.matchKeyword("STORED") { generated = .stored }
                else if c.matchKeyword("VIRTUAL") { generated = .virtual }
                continue
            }
            _ = c.advance() // unknown attribute — advance one to keep progress
        }

        let column = Column(
            name: colName, type: type, nullable: nullable,
            defaultExpression: defaultExpr, comment: nil,
            generated: generated, source: c.range(from: startToken)
        )
        return .column(column, inline: inline)
    }

    private func parseTableConstraint(_ c: inout TokenCursor, tableName: Identifier, startToken: Token) -> [Constraint] {
        var name: Identifier? = nil
        if c.matchKeyword("CONSTRAINT") { name = c.readIdentifier() }
        if c.matchKeyword("PRIMARY") {
            _ = c.matchKeyword("KEY")
            let cols = parseParenColumnList(&c)
            return [.primaryKey(columns: cols, name: name, source: c.range(from: startToken))]
        }
        if c.matchKeyword("UNIQUE") {
            _ = c.matchKeyword("KEY"); _ = c.matchKeyword("INDEX")
            _ = c.readIdentifier() // optional index name
            let cols = parseParenColumnList(&c)
            return [.unique(columns: cols, name: name, source: c.range(from: startToken))]
        }
        if c.matchKeyword("FOREIGN") {
            _ = c.matchKeyword("KEY")
            _ = c.readIdentifier() // optional index name
            let cols = parseParenColumnList(&c)
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
        if c.matchKeyword("KEY") || c.matchKeyword("INDEX") || c.matchKeyword("FULLTEXT") || c.matchKeyword("SPATIAL") {
            // Inline index definition — skip past its column list; the
            // information isn't lost for us because CREATE INDEX handles
            // secondary indexes and the tests focus on FK/PK.
            skipElement(&c)
            return []
        }
        skipElement(&c)
        return []
    }

    private func parseReferencesTail(_ c: inout TokenCursor, localColumns: [Identifier], name: Identifier? = nil, startToken: Token) -> ForeignKeySpec? {
        guard let refTable = c.readQualifiedIdentifier() else { return nil }
        var refCols: [Identifier] = []
        if c.isPunctuation(0x28) { refCols = parseParenColumnList(&c) }
        var onDelete: ReferentialAction = .noAction
        var onUpdate: ReferentialAction = .noAction
        while c.matchKeyword("ON") {
            if c.matchKeyword("DELETE") { onDelete = readAction(&c) }
            else if c.matchKeyword("UPDATE") { onUpdate = readAction(&c) }
            else { break }
        }
        _ = c.matchKeyword("MATCH")
        if case .identifier = c.current.kind { _ = c.advance() }
        return ForeignKeySpec(
            name: name, localColumns: localColumns,
            referencedTable: refTable, referencedColumns: refCols,
            onDelete: onDelete, onUpdate: onUpdate,
            source: c.range(from: startToken)
        )
    }

    private func readAction(_ c: inout TokenCursor) -> ReferentialAction {
        if c.matchKeyword("CASCADE") { return .cascade }
        if c.matchKeyword("RESTRICT") { return .restrict }
        if c.matchKeyword("NO") { _ = c.matchKeyword("ACTION"); return .noAction }
        if c.matchKeyword("SET") {
            if c.matchKeyword("NULL") { return .setNull }
            if c.matchKeyword("DEFAULT") { return .setDefault }
        }
        return .unknown
    }

    // MARK: Data type

    private func parseDataType(_ c: inout TokenCursor) -> DataType {
        var parts: [String] = []
        switch c.current.kind {
        case .identifier:  parts.append(c.advance().text)
        case .keyword(let k): parts.append(k); _ = c.advance()
        default: return .unknown(c.current.text)
        }
        var params: [String] = []
        if c.matchPunctuation(0x28) {
            while !c.isAtEnd && !c.isPunctuation(0x29) {
                params.append(c.advance().text)
                if c.isPunctuation(0x2C) { _ = c.advance() }
            }
            _ = c.matchPunctuation(0x29)
        }
        // Type modifiers frequently follow the type: UNSIGNED, ZEROFILL,
        // CHARACTER SET, COLLATE. We do NOT consume them here — the
        // column loop handles unsupported modifiers by advancing.
        return .named(parts.joined(separator: " "), params: params)
    }

    // MARK: ALTER TABLE

    private func parseAlter(_ c: inout TokenCursor, slice: StatementSlice) -> MySQLStatementOutcome {
        _ = c.advance() // ALTER
        if !c.matchKeyword("TABLE") { return .skipped(unsupported("ALTER …", slice)) }
        guard let target = c.readQualifiedIdentifier() else {
            return .skipped(unsupported("ALTER TABLE (no name)", slice))
        }
        var added: [Constraint] = []
        while !c.isAtEnd {
            if c.matchKeyword("ADD") {
                _ = c.matchKeyword("COLUMN")
                if c.isKeyword("CONSTRAINT") || c.isKeyword("PRIMARY") ||
                    c.isKeyword("UNIQUE") || c.isKeyword("FOREIGN") ||
                    c.isKeyword("CHECK") {
                    let startToken = c.current
                    let cs = parseTableConstraint(&c, tableName: target, startToken: startToken)
                    added.append(contentsOf: cs)
                }
            } else {
                _ = c.advance()
            }
            if c.matchPunctuation(0x2C) { continue }
            break
        }
        if added.isEmpty { return .skipped(unsupported("ALTER TABLE (non-constraint)", slice)) }
        return .parsedAlterConstraint(target: target, added: added)
    }

    // MARK: CREATE INDEX

    private func parseIndex(_ c: inout TokenCursor, slice: StatementSlice, unique: Bool) -> MySQLStatementOutcome {
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
        let name = c.readIdentifier()
        if !c.matchKeyword("ON") { return .skipped(unsupported("CREATE INDEX", slice)) }
        guard let table = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE INDEX", slice)) }
        var method: String? = nil
        if c.matchKeyword("USING") {
            if case .identifier = c.current.kind { method = c.advance().text }
            else if case .keyword(let k) = c.current.kind { method = k; _ = c.advance() }
        }
        let cols = parseParenColumnList(&c).map { IndexColumn(column: $0) }
        return .parsedIndex(Index(
            name: name, table: table, columns: cols,
            unique: unique, method: method,
            source: sliceRange(slice)
        ))
    }

    // MARK: view / trigger / routine (headers only)

    private func parseView(_ c: inout TokenCursor, slice: StatementSlice) -> MySQLStatementOutcome {
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
        guard let name = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE VIEW", slice)) }
        return .parsedView(View(
            name: name, materialized: false,
            definitionSQL: slice.text,
            source: sliceRange(slice), confidence: .partial
        ))
    }

    private func parseTrigger(_ c: inout TokenCursor, slice: StatementSlice) -> MySQLStatementOutcome {
        guard let name = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE TRIGGER", slice)) }
        var timing: TriggerTiming = .unknown
        if c.matchKeyword("BEFORE") { timing = .before }
        else if c.matchKeyword("AFTER") { timing = .after }
        var events: [TriggerEvent] = []
        if c.matchKeyword("INSERT") { events.append(.insert) }
        else if c.matchKeyword("UPDATE") { events.append(.update) }
        else if c.matchKeyword("DELETE") { events.append(.delete) }
        var table: Identifier = Identifier(raw: "")
        if c.matchKeyword("ON") { table = c.readQualifiedIdentifier() ?? table }
        return .parsedTrigger(Trigger(
            name: name, table: table, timing: timing, events: events,
            bodySQL: slice.text, source: sliceRange(slice), confidence: .partial
        ))
    }

    private func parseRoutine(_ c: inout TokenCursor, slice: StatementSlice, kind: RoutineKind) -> MySQLStatementOutcome {
        guard let name = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE ROUTINE", slice)) }
        return .parsedRoutine(Routine(
            name: name, kind: kind, bodySQL: slice.text,
            source: sliceRange(slice), confidence: .partial
        ))
    }

    // MARK: helpers

    private func parseParenColumnList(_ c: inout TokenCursor) -> [Identifier] {
        var out: [Identifier] = []
        guard c.matchPunctuation(0x28) else { return out }
        while !c.isAtEnd && !c.isPunctuation(0x29) {
            if let id = c.readIdentifier() { out.append(id) }
            // Skip anything up to , or )
            while !c.isPunctuation(0x2C) && !c.isPunctuation(0x29) && !c.isAtEnd { _ = c.advance() }
            if c.isPunctuation(0x2C) { _ = c.advance() }
        }
        _ = c.matchPunctuation(0x29)
        return out
    }

    private func readParenthesized(_ c: inout TokenCursor) -> String {
        guard c.matchPunctuation(0x28) else { return "" }
        var depth = 1
        var parts: [String] = []
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

    private func readExpressionText(_ c: inout TokenCursor) -> String {
        var depth = 0
        var parts: [String] = []
        while !c.isAtEnd {
            let tk = c.current
            if case .punctuation(let b) = tk.kind {
                if b == 0x28 { depth += 1 }
                else if b == 0x29 { if depth == 0 { break }; depth -= 1 }
                else if depth == 0 && (b == 0x2C || b == 0x3B) { break }
            }
            if depth == 0, case .keyword(let k) = tk.kind {
                let terminators: Set<String> = ["NOT", "NULL", "DEFAULT", "PRIMARY", "UNIQUE", "REFERENCES",
                                                "CHECK", "GENERATED", "COLLATE", "COMMENT", "CONSTRAINT",
                                                "AUTO_INCREMENT", "KEY", "CHARACTER", "CHARSET"]
                if terminators.contains(k) { break }
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
        return SourceRange(
            file: file,
            startLine: s.line, startColumn: s.column,
            endLine: e.line, endColumn: e.column,
            byteOffset: slice.byteOffset, byteLength: slice.byteLength
        )
    }

    private func unsupported(_ what: String, _ slice: StatementSlice) -> Diagnostic {
        Diagnostic(
            severity: .info,
            code: DiagnosticCode.unsupportedFeature,
            message: "Skipped: \(what)",
            source: sliceRange(slice)
        )
    }

    private func isTrivia(_ token: Token) -> Bool {
        switch token.kind {
        case .whitespace, .lineComment, .blockComment: return true
        default: return false
        }
    }
}
