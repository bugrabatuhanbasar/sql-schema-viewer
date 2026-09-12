import Foundation
import SchemaModel
import SQLLexer
import ParserCore

public struct SQLiteParser: StatementParser {
    public static var dialect: Dialect { .sqlite }
    public init() {}

    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        let buffer = SourceBuffer(source, file: file)
        let index = LineIndex(buffer)
        let splitter = StatementSplitter(config: SQLiteKeywords.config)
        let slices = splitter.split(buffer)

        var schema = Schema(dialect: .sqlite)
        var diagnostics: [Diagnostic] = []
        var pendingIndexes: [Index] = []

        var fully = 0, partial = 0, skipped = 0
        let recognizer = SQLiteStatementRecognizer(file: file, lineIndex: index)

        for slice in slices {
            switch recognizer.recognize(slice: slice) {
            case .parsedTable(let t):
                schema.tables[t.name] = t
                if t.confidence == .partial { partial += 1 } else { fully += 1 }
            case .parsedIndex(let i): pendingIndexes.append(i); fully += 1
            case .parsedView(let v): schema.views[v.name] = v; partial += 1
            case .parsedTrigger(let t): schema.triggers[t.name] = t; partial += 1
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
        schema.stats = AnalysisStats(fullyParsedObjects: fully, partiallyParsedObjects: partial, skippedStatements: skipped)
        schema.diagnostics = diagnostics
        return ParseResult(value: schema, diagnostics: diagnostics)
    }
}

enum SQLiteStatementOutcome {
    case parsedTable(Table)
    case parsedIndex(Index)
    case parsedView(View)
    case parsedTrigger(Trigger)
    case skipped(Diagnostic)
    case ignored
}

struct SQLiteStatementRecognizer {
    let file: URL?
    let lineIndex: LineIndex

    func recognize(slice: StatementSlice) -> SQLiteStatementOutcome {
        var c = TokenCursor(
            tokens: slice.tokens.filter { !isTrivia($0) },
            file: file,
            lineIndex: lineIndex
        )
        guard !c.isAtEnd else { return .ignored }
        for kw in ["SELECT", "INSERT", "UPDATE", "DELETE", "PRAGMA",
                   "BEGIN", "COMMIT", "ROLLBACK", "ATTACH", "DETACH",
                   "REINDEX", "ANALYZE", "VACUUM", "SAVEPOINT", "RELEASE"] {
            if c.isKeyword(kw) { return .ignored }
        }
        if c.isKeyword("CREATE") { return parseCreate(&c, slice: slice) }
        if c.isKeyword("ALTER") { return .ignored } // SQLite ALTER TABLE limited; not schema-defining for us
        if c.isKeyword("DROP") { return .ignored }
        return .skipped(unsupported("Unrecognized statement", slice))
    }

    private func parseCreate(_ c: inout TokenCursor, slice: StatementSlice) -> SQLiteStatementOutcome {
        _ = c.advance() // CREATE
        let temporary = c.matchKeyword("TEMPORARY") || c.matchKeyword("TEMP")
        let unique = c.matchKeyword("UNIQUE")
        if c.matchKeyword("TABLE") { return parseTable(&c, slice: slice, temporary: temporary) }
        if c.matchKeyword("INDEX") { return parseIndex(&c, slice: slice, unique: unique) }
        if c.matchKeyword("VIEW") { return parseView(&c, slice: slice) }
        if c.matchKeyword("TRIGGER") { return parseTrigger(&c, slice: slice) }
        return .skipped(unsupported("CREATE …", slice))
    }

    // CREATE TABLE
    private func parseTable(_ c: inout TokenCursor, slice: StatementSlice, temporary: Bool) -> SQLiteStatementOutcome {
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
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
        // Trailing `WITHOUT ROWID` etc. are ignored — no data change to us.
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
                nullable = false
                _ = c.matchKeyword("ASC") || c.matchKeyword("DESC")
                if c.matchKeyword("ON") { _ = c.matchKeyword("CONFLICT"); _ = c.advance() }
                if c.matchKeyword("AUTOINCREMENT") { generated = .byDefault }
                continue
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
            if c.matchKeyword("COLLATE") { _ = c.advance(); continue }
            if c.matchKeyword("GENERATED") {
                _ = c.matchKeyword("ALWAYS"); _ = c.matchKeyword("AS")
                _ = readParenthesized(&c)
                if c.matchKeyword("STORED") { generated = .stored }
                else if c.matchKeyword("VIRTUAL") { generated = .virtual }
                continue
            }
            _ = c.advance()
        }
        let col = Column(name: colName, type: type, nullable: nullable, defaultExpression: defaultExpr, generated: generated, source: c.range(from: start))
        return .column(col, inline: inline)
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
        var onUpdate: ReferentialAction = .noAction
        while c.matchKeyword("ON") {
            if c.matchKeyword("DELETE") { onDelete = readAction(&c) }
            else if c.matchKeyword("UPDATE") { onUpdate = readAction(&c) }
            else { break }
        }
        var deferrable = false
        if c.matchKeyword("DEFERRABLE") {
            deferrable = true
            _ = c.matchKeyword("INITIALLY")
            _ = c.matchKeyword("DEFERRED") || c.matchKeyword("IMMEDIATE")
        } else if c.matchKeyword("NOT") { _ = c.matchKeyword("DEFERRABLE") }
        return ForeignKeySpec(name: name, localColumns: localColumns, referencedTable: refTable, referencedColumns: refCols, onDelete: onDelete, onUpdate: onUpdate, deferrable: deferrable, source: c.range(from: startToken))
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

    private func parseType(_ c: inout TokenCursor) -> DataType {
        // SQLite type is optional — column names can appear without a type.
        switch c.current.kind {
        case .identifier, .keyword:
            var name: String
            if case .keyword(let k) = c.current.kind {
                // Terminators means no type at all.
                if ["PRIMARY", "UNIQUE", "REFERENCES", "CHECK", "NOT", "NULL", "DEFAULT", "COLLATE", "GENERATED", "CONSTRAINT"].contains(k) {
                    return .unknown("")
                }
                name = k; _ = c.advance()
            } else {
                name = c.advance().text
            }
            var params: [String] = []
            if c.matchPunctuation(0x28) {
                while !c.isAtEnd && !c.isPunctuation(0x29) {
                    params.append(c.advance().text)
                    if c.isPunctuation(0x2C) { _ = c.advance() }
                }
                _ = c.matchPunctuation(0x29)
            }
            return .named(name, params: params)
        default:
            return .unknown("")
        }
    }

    private func parseIndex(_ c: inout TokenCursor, slice: StatementSlice, unique: Bool) -> SQLiteStatementOutcome {
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
        let name = c.readIdentifier()
        if !c.matchKeyword("ON") { return .skipped(unsupported("CREATE INDEX", slice)) }
        guard let table = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE INDEX", slice)) }
        let cols = parseParenColumns(&c).map { IndexColumn(column: $0) }
        var predicate: String? = nil
        if c.matchKeyword("WHERE") { predicate = readExpression(&c) }
        return .parsedIndex(Index(name: name, table: table, columns: cols, unique: unique, predicate: predicate, source: sliceRange(slice)))
    }

    private func parseView(_ c: inout TokenCursor, slice: StatementSlice) -> SQLiteStatementOutcome {
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
        guard let name = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE VIEW", slice)) }
        return .parsedView(View(name: name, definitionSQL: slice.text, source: sliceRange(slice), confidence: .partial))
    }

    private func parseTrigger(_ c: inout TokenCursor, slice: StatementSlice) -> SQLiteStatementOutcome {
        _ = c.matchKeywords(["IF", "NOT", "EXISTS"])
        guard let name = c.readQualifiedIdentifier() else { return .skipped(unsupported("CREATE TRIGGER", slice)) }
        var timing: TriggerTiming = .unknown
        if c.matchKeyword("BEFORE") { timing = .before }
        else if c.matchKeyword("AFTER") { timing = .after }
        else if c.matchKeywords(["INSTEAD", "OF"]) { timing = .insteadOf }
        var events: [TriggerEvent] = []
        if c.matchKeyword("INSERT") { events.append(.insert) }
        else if c.matchKeyword("UPDATE") { events.append(.update) }
        else if c.matchKeyword("DELETE") { events.append(.delete) }
        var table: Identifier = Identifier(raw: "")
        if c.matchKeyword("ON") { table = c.readQualifiedIdentifier() ?? table }
        return .parsedTrigger(Trigger(name: name, table: table, timing: timing, events: events, bodySQL: slice.text, source: sliceRange(slice), confidence: .partial))
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
                let stops: Set<String> = ["NOT", "NULL", "DEFAULT", "PRIMARY", "UNIQUE", "REFERENCES", "CHECK", "GENERATED", "COLLATE", "CONSTRAINT"]
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
    private func isTrivia(_ t: Token) -> Bool {
        switch t.kind { case .whitespace, .lineComment, .blockComment: return true; default: return false }
    }
}
