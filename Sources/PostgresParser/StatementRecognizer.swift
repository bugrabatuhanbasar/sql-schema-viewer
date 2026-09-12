import Foundation
import SchemaModel
import SQLLexer
import ParserCore

enum StatementOutcome {
    case parsedTable(Table)
    case parsedIndex(Index)
    case parsedAlterConstraint(target: Identifier, added: [Constraint])
    case parsedTableComment(table: Identifier, comment: String)
    case parsedColumnComment(table: Identifier, column: Identifier, comment: String)
    case parsedView(View)
    case parsedTrigger(Trigger)
    case parsedRoutine(Routine)
    case partial(Diagnostic)
    case skipped(Diagnostic)
    case ignored // no-op statements like SET, BEGIN, COMMIT
}

/// Top-level dispatch over a statement slice. Never throws; every failure
/// path yields a diagnostic so the caller can keep going.
struct PostgresStatementRecognizer {
    let file: URL?
    let lineIndex: LineIndex

    func recognize(slice: StatementSlice) -> StatementOutcome {
        var cursor = TokenCursor(
            tokens: slice.tokens.filter { !isTrivia($0) },
            file: file,
            lineIndex: lineIndex
        )
        guard !cursor.isAtEnd else { return .ignored }

        // Skip leading `EXPLAIN`, `WITH` etc — not schema-defining.
        if cursor.isKeyword("SELECT") || cursor.isKeyword("INSERT") ||
            cursor.isKeyword("UPDATE") || cursor.isKeyword("DELETE") ||
            cursor.isKeyword("SET") || cursor.isKeyword("BEGIN") ||
            cursor.isKeyword("COMMIT") || cursor.isKeyword("ROLLBACK") ||
            cursor.isKeyword("GRANT") || cursor.isKeyword("REVOKE") ||
            cursor.isKeyword("DO") {
            return .ignored
        }

        if cursor.isKeyword("COMMENT") {
            return parseComment(&cursor, slice: slice)
        }

        if cursor.isKeyword("CREATE") {
            return parseCreate(&cursor, slice: slice)
        }

        if cursor.isKeyword("ALTER") {
            return parseAlter(&cursor, slice: slice)
        }

        if cursor.isKeyword("DROP") {
            return .ignored
        }

        return .skipped(Diagnostic(
            severity: .info,
            code: DiagnosticCode.skippedStatement,
            message: "Unrecognized statement",
            source: sliceRange(slice)
        ))
    }

    // MARK: CREATE dispatch

    private func parseCreate(_ c: inout TokenCursor, slice: StatementSlice) -> StatementOutcome {
        _ = c.advance() // CREATE
        _ = c.matchKeyword("OR"); _ = c.matchKeyword("REPLACE")
        _ = c.matchKeyword("GLOBAL"); _ = c.matchKeyword("LOCAL")
        let temporary = c.matchKeyword("TEMPORARY") || c.matchKeyword("TEMP")
        let unlogged = c.matchKeyword("UNLOGGED")
        let unique = c.matchKeyword("UNIQUE")

        if c.matchKeyword("MATERIALIZED") {
            if c.matchKeyword("VIEW") { return parseCreateView(&c, slice: slice, materialized: true) }
            return .skipped(unsupported("CREATE MATERIALIZED …", slice))
        }
        if c.matchKeyword("VIEW") { return parseCreateView(&c, slice: slice, materialized: false) }
        if c.matchKeyword("TABLE") { return parseCreateTable(&c, slice: slice, temporary: temporary, unlogged: unlogged) }
        if c.matchKeyword("INDEX") { return parseCreateIndex(&c, slice: slice, unique: unique) }
        if c.matchKeyword("TRIGGER") { return parseCreateTrigger(&c, slice: slice) }
        if c.matchKeyword("FUNCTION") { return parseCreateRoutine(&c, slice: slice, kind: .function) }
        if c.matchKeyword("PROCEDURE") { return parseCreateRoutine(&c, slice: slice, kind: .procedure) }
        return .skipped(unsupported("CREATE …", slice))
    }

    // MARK: CREATE TABLE

    private func parseCreateTable(_ c: inout TokenCursor, slice: StatementSlice, temporary: Bool, unlogged: Bool) -> StatementOutcome {
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
        guard let name = c.readQualifiedIdentifier() else {
            return .skipped(unexpectedToken(c.current, slice: slice))
        }
        // Skip optional `PARTITION OF parent (…)` variants — we only need the header.
        if c.matchKeyword("PARTITION") {
            _ = c.matchKeyword("OF")
            _ = c.readQualifiedIdentifier()
        }

        guard c.matchPunctuation(0x28) else { // '('
            // Could be `CREATE TABLE t AS SELECT …` — treat as a bare table
            // with no columns; we only capture the name so cross-references
            // still resolve.
            let table = Table(
                name: name,
                kind: kindFor(temporary: temporary, unlogged: unlogged),
                source: sliceRange(slice),
                confidence: .partial
            )
            return .parsedTable(table)
        }

        var columns: [Column] = []
        var constraints: [Constraint] = []
        var partial = false

        while !c.isAtEnd && !c.isPunctuation(0x29) {
            let element = parseTableElement(&c, tableName: name)
            switch element {
            case .column(let col, let inline):
                columns.append(col)
                constraints.append(contentsOf: inline)
            case .tableConstraint(let cs):
                constraints.append(contentsOf: cs)
            case .partial:
                partial = true
            }
            if c.matchPunctuation(0x2C) { continue } // ','
            break
        }
        _ = c.matchPunctuation(0x29)
        // Fold per-column NOT NULL / inline PRIMARY KEY into constraint list.
        for col in columns {
            if !col.nullable {
                constraints.append(.notNull(column: col.name, source: col.source))
            }
        }

        let table = Table(
            name: name,
            columns: columns,
            constraints: constraints,
            indexes: [],
            kind: kindFor(temporary: temporary, unlogged: unlogged),
            source: sliceRange(slice),
            confidence: partial ? .partial : .complete
        )
        return .parsedTable(table)
    }

    private enum TableElement {
        case column(Column, inline: [Constraint])
        case tableConstraint([Constraint])
        case partial
    }

    private func kindFor(temporary: Bool, unlogged: Bool) -> TableKind {
        if temporary { return .temporary }
        if unlogged { return .unlogged }
        return .regular
    }

    /// One comma-separated element inside `CREATE TABLE (...)`. Either a
    /// column definition or a table-level constraint.
    private func parseTableElement(_ c: inout TokenCursor, tableName: Identifier) -> TableElement {
        let startToken = c.current
        // Table-level constraint?
        if c.isKeyword("CONSTRAINT") || c.isKeyword("PRIMARY") ||
            c.isKeyword("UNIQUE") || c.isKeyword("FOREIGN") ||
            c.isKeyword("CHECK") || c.isKeyword("EXCLUDE") {
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
        var comment: String? = nil
        var generated: GeneratedKind? = nil
        var inline: [Constraint] = []

        while !c.isAtEnd && !c.isPunctuation(0x2C) && !c.isPunctuation(0x29) {
            if c.matchKeyword("NOT") {
                if c.matchKeyword("NULL") { nullable = false; continue }
            }
            if c.matchKeyword("NULL") { nullable = true; continue }
            if c.matchKeyword("DEFAULT") {
                defaultExpr = readExpressionText(&c)
                continue
            }
            if c.matchKeyword("PRIMARY") {
                _ = c.matchKeyword("KEY")
                inline.append(.primaryKey(columns: [colName], name: nil, source: c.range(from: startToken)))
                nullable = false
                continue
            }
            if c.matchKeyword("UNIQUE") {
                inline.append(.unique(columns: [colName], name: nil, source: c.range(from: startToken)))
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
                inline.append(.check(expression: expr, name: nil, source: c.range(from: startToken)))
                continue
            }
            if c.matchKeyword("GENERATED") {
                _ = c.matchKeyword("ALWAYS") || c.matchKeyword("BY")
                _ = c.matchKeyword("DEFAULT")
                _ = c.matchKeyword("AS")
                if c.matchKeyword("IDENTITY") { generated = .always; continue }
                // STORED
                _ = readParenthesized(&c)
                _ = c.matchKeyword("STORED")
                generated = .stored
                continue
            }
            if c.matchKeyword("COLLATE") { _ = c.advance(); continue }
            // Unknown modifier — advance one token to keep progress.
            _ = c.advance()
        }

        let column = Column(
            name: colName,
            type: type,
            nullable: nullable,
            defaultExpression: defaultExpr,
            comment: comment,
            generated: generated,
            source: c.range(from: startToken)
        )
        return .column(column, inline: inline)
    }

    /// A table-level constraint block (`PRIMARY KEY (...)`, `UNIQUE (...)`,
    /// `FOREIGN KEY (...) REFERENCES ...`, `CHECK (...)`). Returns the
    /// resulting constraints; also consumes an optional leading
    /// `CONSTRAINT name`.
    private func parseTableConstraint(_ c: inout TokenCursor, tableName: Identifier, startToken: Token) -> [Constraint] {
        var name: Identifier? = nil
        if c.matchKeyword("CONSTRAINT") { name = c.readIdentifier() }

        if c.matchKeyword("PRIMARY") {
            _ = c.matchKeyword("KEY")
            let cols = parseParenColumnList(&c)
            return [.primaryKey(columns: cols, name: name, source: c.range(from: startToken))]
        }
        if c.matchKeyword("UNIQUE") {
            let cols = parseParenColumnList(&c)
            return [.unique(columns: cols, name: name, source: c.range(from: startToken))]
        }
        if c.matchKeyword("FOREIGN") {
            _ = c.matchKeyword("KEY")
            let cols = parseParenColumnList(&c)
            if !c.matchKeyword("REFERENCES") {
                return []
            }
            if let fk = parseReferencesTail(&c, localColumns: cols, name: name, startToken: startToken) {
                return [.foreignKey(fk)]
            }
            return []
        }
        if c.matchKeyword("CHECK") {
            let expr = readParenthesized(&c)
            return [.check(expression: expr, name: name, source: c.range(from: startToken))]
        }
        if c.matchKeyword("EXCLUDE") {
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
            if c.matchKeyword("DELETE") { onDelete = readReferentialAction(&c) }
            else if c.matchKeyword("UPDATE") { onUpdate = readReferentialAction(&c) }
            else { break }
        }
        var deferrable = false
        if c.matchKeyword("DEFERRABLE") {
            deferrable = true
            _ = c.matchKeyword("INITIALLY")
            _ = c.matchKeyword("DEFERRED") || c.matchKeyword("IMMEDIATE")
        } else if c.matchKeyword("NOT") {
            _ = c.matchKeyword("DEFERRABLE")
        }
        _ = c.matchKeyword("MATCH")
        if case .identifier = c.current.kind { _ = c.advance() }
        return ForeignKeySpec(
            name: name,
            localColumns: localColumns,
            referencedTable: refTable,
            referencedColumns: refCols,
            onDelete: onDelete,
            onUpdate: onUpdate,
            deferrable: deferrable,
            source: c.range(from: startToken)
        )
    }

    private func readReferentialAction(_ c: inout TokenCursor) -> ReferentialAction {
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
        // Read type name (may be qualified or multi-word like `DOUBLE PRECISION`
        // or `TIMESTAMP WITH TIME ZONE`).
        var parts: [String] = []
        if case .identifier = c.current.kind {
            parts.append(c.advance().text)
        } else if case .keyword(let k) = c.current.kind {
            parts.append(k)
            _ = c.advance()
        } else {
            return .unknown(c.current.text)
        }
        // Multi-word combos
        if c.isKeyword("PRECISION") { parts.append("PRECISION"); _ = c.advance() }
        while c.isKeyword("WITH") || c.isKeyword("WITHOUT") {
            parts.append(c.advance().text)
            if c.isKeyword("TIME") { parts.append(c.advance().text) }
            if c.isKeyword("ZONE") { parts.append(c.advance().text) }
        }

        // Params
        var params: [String] = []
        if c.matchPunctuation(0x28) {
            while !c.isAtEnd && !c.isPunctuation(0x29) {
                let tk = c.advance()
                params.append(tk.text)
                if c.isPunctuation(0x2C) { _ = c.advance() }
            }
            _ = c.matchPunctuation(0x29)
        }

        var type: DataType = .named(parts.joined(separator: " "), params: params)

        // Array suffix: `TEXT[]` or `INT ARRAY`
        var dims = 0
        while c.matchPunctuation(0x5B) { // '['
            // Optional dimension size
            while !c.isPunctuation(0x5D) && !c.isAtEnd { _ = c.advance() }
            _ = c.matchPunctuation(0x5D)
            dims += 1
        }
        if c.matchKeyword("ARRAY") { dims = max(dims, 1) }
        if dims > 0 { type = .array(type, dimensions: dims) }
        return type
    }

    // MARK: helpers

    private func parseParenColumnList(_ c: inout TokenCursor) -> [Identifier] {
        var out: [Identifier] = []
        guard c.matchPunctuation(0x28) else { return out }
        while !c.isAtEnd && !c.isPunctuation(0x29) {
            if let id = c.readIdentifier() { out.append(id) }
            // Skip optional `ASC/DESC NULLS FIRST/LAST` inside index-like lists.
            while !c.isPunctuation(0x2C) && !c.isPunctuation(0x29) && !c.isAtEnd {
                _ = c.advance()
            }
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
                else if b == 0x29 {
                    depth -= 1
                    if depth == 0 { _ = c.advance(); break }
                }
            }
            parts.append(tk.text)
            _ = c.advance()
        }
        return parts.joined(separator: " ")
    }

    private func readExpressionText(_ c: inout TokenCursor) -> String {
        var parts: [String] = []
        var depth = 0
        while !c.isAtEnd {
            let tk = c.current
            if case .punctuation(let b) = tk.kind {
                if b == 0x28 { depth += 1 }
                else if b == 0x29 {
                    if depth == 0 { break }
                    depth -= 1
                }
                else if depth == 0 && (b == 0x2C || b == 0x3B) { break }
            }
            if depth == 0 {
                if case .keyword(let k) = tk.kind {
                    let terminators: Set<String> = ["NOT", "NULL", "DEFAULT", "PRIMARY", "UNIQUE", "REFERENCES", "CHECK", "GENERATED", "COLLATE", "CONSTRAINT"]
                    if terminators.contains(k) { break }
                }
            }
            parts.append(tk.text)
            _ = c.advance()
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

    // MARK: ALTER TABLE

    private func parseAlter(_ c: inout TokenCursor, slice: StatementSlice) -> StatementOutcome {
        _ = c.advance() // ALTER
        if !c.matchKeyword("TABLE") { return .skipped(unsupported("ALTER …", slice)) }
        _ = c.matchKeywords(["IF", "EXISTS"])
        _ = c.matchKeyword("ONLY")
        guard let target = c.readQualifiedIdentifier() else {
            return .skipped(unexpectedToken(c.current, slice: slice))
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
        if added.isEmpty {
            return .skipped(unsupported("ALTER TABLE (non-constraint)", slice))
        }
        return .parsedAlterConstraint(target: target, added: added)
    }

    // MARK: CREATE INDEX

    private func parseCreateIndex(_ c: inout TokenCursor, slice: StatementSlice, unique: Bool) -> StatementOutcome {
        _ = c.matchKeyword("CONCURRENTLY")
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
        var name: Identifier? = nil
        // Optional index name — may be absent (PG allows `CREATE INDEX ON table (...)`)
        if !c.isKeyword("ON") {
            name = c.readIdentifier()
        }
        if !c.matchKeyword("ON") {
            return .skipped(unexpectedToken(c.current, slice: slice))
        }
        _ = c.matchKeyword("ONLY")
        guard let table = c.readQualifiedIdentifier() else {
            return .skipped(unexpectedToken(c.current, slice: slice))
        }
        var method: String? = nil
        if c.matchKeyword("USING") {
            if case .identifier = c.current.kind { method = c.advance().text }
            else if case .keyword(let k) = c.current.kind { method = k; _ = c.advance() }
        }
        let cols = parseParenColumnList(&c).map { IndexColumn(column: $0) }
        var predicate: String? = nil
        if c.matchKeyword("WHERE") {
            predicate = readExpressionText(&c)
        }
        let index = Index(
            name: name,
            table: table,
            columns: cols,
            unique: unique,
            method: method,
            predicate: predicate,
            source: sliceRange(slice)
        )
        return .parsedIndex(index)
    }

    // MARK: COMMENT ON

    private func parseComment(_ c: inout TokenCursor, slice: StatementSlice) -> StatementOutcome {
        _ = c.advance() // COMMENT
        _ = c.matchKeyword("ON")
        if c.matchKeyword("TABLE") {
            guard let table = c.readQualifiedIdentifier() else { return .skipped(unsupported("COMMENT", slice)) }
            _ = c.matchKeyword("IS")
            let text = extractStringLiteral(&c) ?? ""
            return .parsedTableComment(table: table, comment: text)
        }
        if c.matchKeyword("COLUMN") {
            // Accept `table.column` (two-part). Three-part `schema.table.column`
            // is deferred to M4.
            guard let qualified = c.readQualifiedIdentifier(),
                  let tableName = qualified.schema else {
                return .skipped(unsupported("COMMENT COLUMN (unqualified)", slice))
            }
            _ = c.matchKeyword("IS")
            let text = extractStringLiteral(&c) ?? ""
            return .parsedColumnComment(
                table: Identifier(raw: tableName),
                column: Identifier(raw: qualified.raw),
                comment: text
            )
        }
        return .skipped(unsupported("COMMENT", slice))
    }

    private func extractStringLiteral(_ c: inout TokenCursor) -> String? {
        if case .stringLiteral = c.current.kind {
            var raw = c.advance().text
            if raw.hasPrefix("'") && raw.hasSuffix("'") {
                raw = String(raw.dropFirst().dropLast())
                raw = raw.replacingOccurrences(of: "''", with: "'")
            }
            return raw
        }
        return nil
    }

    // MARK: CREATE VIEW / MATERIALIZED VIEW (header only in M2)

    private func parseCreateView(_ c: inout TokenCursor, slice: StatementSlice, materialized: Bool) -> StatementOutcome {
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
        guard let name = c.readQualifiedIdentifier() else {
            return .skipped(unexpectedToken(c.current, slice: slice))
        }
        // Everything else is the SELECT body — we store as opaque text.
        let body = slice.text
        return .parsedView(View(
            name: name,
            materialized: materialized,
            definitionSQL: body,
            source: sliceRange(slice),
            confidence: .partial
        ))
    }

    // MARK: CREATE TRIGGER / FUNCTION / PROCEDURE (header only in M2)

    private func parseCreateTrigger(_ c: inout TokenCursor, slice: StatementSlice) -> StatementOutcome {
        guard let name = c.readIdentifier() else {
            return .skipped(unexpectedToken(c.current, slice: slice))
        }
        var timing: TriggerTiming = .unknown
        if c.matchKeyword("BEFORE") { timing = .before }
        else if c.matchKeyword("AFTER") { timing = .after }
        else if c.matchKeywords(["INSTEAD", "OF"]) { timing = .insteadOf }
        var events: [TriggerEvent] = []
        while true {
            if c.matchKeyword("INSERT") { events.append(.insert) }
            else if c.matchKeyword("UPDATE") { events.append(.update) }
            else if c.matchKeyword("DELETE") { events.append(.delete) }
            else if c.matchKeyword("TRUNCATE") { events.append(.truncate) }
            else { break }
            if !c.matchKeyword("OR") { break }
        }
        var table: Identifier = Identifier(raw: "")
        if c.matchKeyword("ON") { table = c.readQualifiedIdentifier() ?? table }
        return .parsedTrigger(Trigger(
            name: name,
            table: table,
            timing: timing,
            events: events,
            bodySQL: slice.text,
            source: sliceRange(slice),
            confidence: .partial
        ))
    }

    private func parseCreateRoutine(_ c: inout TokenCursor, slice: StatementSlice, kind: RoutineKind) -> StatementOutcome {
        guard let name = c.readQualifiedIdentifier() else {
            return .skipped(unexpectedToken(c.current, slice: slice))
        }
        return .parsedRoutine(Routine(
            name: name,
            kind: kind,
            bodySQL: slice.text,
            source: sliceRange(slice),
            confidence: .partial
        ))
    }

    // MARK: diagnostic helpers

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

    private func unexpectedToken(_ token: Token, slice: StatementSlice) -> Diagnostic {
        Diagnostic(
            severity: .warning,
            code: DiagnosticCode.unexpectedToken,
            message: "Unexpected token '\(token.text)'",
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

