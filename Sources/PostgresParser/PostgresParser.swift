import Foundation
import SchemaModel
import SQLLexer
import ParserCore

public struct PostgresParser: StatementParser {
    public static var dialect: Dialect { .postgres }

    public init() {}

    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        let buffer = SourceBuffer(source, file: file)
        let index = LineIndex(buffer)
        let splitter = StatementSplitter(config: PostgresKeywords.postgresConfig)
        let slices = splitter.split(buffer)

        var schema = Schema(dialect: .postgres)
        var diagnostics: [Diagnostic] = []
        let recognizer = PostgresStatementRecognizer(file: file, lineIndex: index)

        var pendingIndexes: [Index] = []
        var pendingConstraints: [(Identifier, [Constraint])] = []
        var pendingTableComments: [(Identifier, String)] = []
        var pendingColumnComments: [(Identifier, Identifier, String)] = []

        var fully = 0, partial = 0, skipped = 0, ignored = 0

        for slice in slices {
            let outcome = recognizer.recognize(slice: slice)
            switch outcome {
            case .parsedTable(let table):
                schema.tables[table.name] = table
                if table.confidence == .partial { partial += 1 } else { fully += 1 }
            case .parsedIndex(let idx):
                pendingIndexes.append(idx)
                fully += 1
            case .parsedAlterConstraint(let target, let added):
                pendingConstraints.append((target, added))
                fully += 1
            case .parsedTableComment(let table, let text):
                pendingTableComments.append((table, text))
                fully += 1
            case .parsedColumnComment(let table, let column, let text):
                pendingColumnComments.append((table, column, text))
                fully += 1
            case .parsedView(let v):
                schema.views[v.name] = v
                partial += 1
            case .parsedTrigger(let t):
                schema.triggers[t.name] = t
                partial += 1
            case .parsedRoutine(let r):
                schema.routines[r.name] = r
                partial += 1
            case .partial(let diag):
                diagnostics.append(diag); partial += 1
            case .skipped(let diag):
                diagnostics.append(diag); skipped += 1
            case .ignored:
                ignored += 1
            }
        }

        // Attach indexes and ALTERs to their tables. Missing target => diagnostic.
        for idx in pendingIndexes {
            if var t = schema.tables[idx.table] {
                t.indexes.append(idx)
                schema.tables[idx.table] = t
            } else {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: DiagnosticCode.danglingReference,
                    message: "Index references unknown table \(idx.table.raw)",
                    source: idx.source
                ))
            }
        }
        for (target, added) in pendingConstraints {
            if var t = schema.tables[target] {
                t.constraints.append(contentsOf: added)
                schema.tables[target] = t
            } else {
                let src = added.first.map { c -> SourceRange in
                    switch c {
                    case .primaryKey(_, _, let s), .unique(_, _, let s), .check(_, _, let s), .notNull(_, let s):
                        return s
                    case .foreignKey(let fk):
                        return fk.source
                    }
                } ?? .zero
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: DiagnosticCode.danglingReference,
                    message: "ALTER TABLE targets unknown table \(target.raw)",
                    source: src
                ))
            }
        }
        for (table, text) in pendingTableComments {
            if var t = schema.tables[table] { t.comment = text; schema.tables[table] = t }
        }
        for (table, column, text) in pendingColumnComments {
            if var t = schema.tables[table] {
                if let ci = t.columns.firstIndex(where: { $0.name.normalized == column.normalized }) {
                    t.columns[ci].comment = text
                    schema.tables[table] = t
                }
            }
        }

        schema.stats = AnalysisStats(
            fullyParsedObjects: fully,
            partiallyParsedObjects: partial,
            skippedStatements: skipped,
            ignoredStatements: ignored
        )
        schema.diagnostics = diagnostics
        return ParseResult(value: schema, diagnostics: diagnostics)
    }
}
