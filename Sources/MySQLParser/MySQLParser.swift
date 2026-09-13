import Foundation
import SchemaModel
import SQLLexer
import ParserCore

public struct MySQLParser: StatementParser {
    public enum Flavor: Sendable {
        case mysql
        case mariadb
    }

    public static var dialect: Dialect { .mysql }
    public let flavor: Flavor

    public init(flavor: Flavor = .mysql) { self.flavor = flavor }

    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        let cfg: LexerConfig = (flavor == .mariadb) ? MySQLKeywords.mariadbConfig : MySQLKeywords.mysqlConfig
        let buffer = SourceBuffer(source, file: file)
        let index = LineIndex(buffer)
        let splitter = StatementSplitter(config: cfg)
        let slices = splitter.split(buffer)

        var schema = Schema(dialect: flavor == .mariadb ? .mariadb : .mysql)
        var diagnostics: [Diagnostic] = []
        var pendingIndexes: [Index] = []
        var pendingConstraints: [(Identifier, [Constraint])] = []

        var fully = 0, partial = 0, skipped = 0, ignored = 0
        let recognizer = MySQLStatementRecognizer(file: file, lineIndex: index, flavor: flavor)

        for slice in slices {
            switch recognizer.recognize(slice: slice) {
            case .parsedTable(let t):
                schema.tables[t.name] = t
                if t.confidence == .partial { partial += 1 } else { fully += 1 }
            case .parsedIndex(let i): pendingIndexes.append(i); fully += 1
            case .parsedAlterConstraint(let target, let added):
                pendingConstraints.append((target, added)); fully += 1
            case .parsedView(let v): schema.views[v.name] = v; partial += 1
            case .parsedTrigger(let t): schema.triggers[t.name] = t; partial += 1
            case .parsedRoutine(let r): schema.routines[r.name] = r; partial += 1
            case .skipped(let d): diagnostics.append(d); skipped += 1
            case .ignored: ignored += 1
            }
        }

        for idx in pendingIndexes {
            if var t = schema.tables[idx.table] {
                t.indexes.append(idx); schema.tables[idx.table] = t
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
                t.constraints.append(contentsOf: added); schema.tables[target] = t
            } else {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    code: DiagnosticCode.danglingReference,
                    message: "ALTER TABLE targets unknown table \(target.raw)",
                    source: .zero
                ))
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
