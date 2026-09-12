import Foundation
import SchemaModel
import SQLLexer
import ParserCore

/// PostgreSQL DDL parser. M1 provides only the type shell; recognizers for
/// CREATE TABLE / ALTER TABLE / CREATE INDEX arrive in M2.
public struct PostgresParser: StatementParser {
    public static var dialect: Dialect { .postgres }

    public init() {}

    public func parse(source: String, file: URL?) -> ParseResult<Schema> {
        let buffer = SourceBuffer(source, file: file)
        let splitter = StatementSplitter(config: .postgres)
        let slices = splitter.split(buffer)

        var schema = Schema(dialect: .postgres)
        schema.stats = AnalysisStats(
            fullyParsedObjects: 0,
            partiallyParsedObjects: 0,
            skippedStatements: slices.count
        )
        var diags: [Diagnostic] = []
        for slice in slices {
            diags.append(Diagnostic(
                severity: .info,
                code: DiagnosticCode.skippedStatement,
                message: "PostgreSQL statement recognition not yet implemented (M2)",
                source: SourceRange(
                    file: file,
                    startLine: 0, startColumn: 0, endLine: 0, endColumn: 0,
                    byteOffset: slice.byteOffset, byteLength: slice.byteLength
                )
            ))
        }
        schema.diagnostics = diags
        return ParseResult(value: schema, diagnostics: diags)
    }
}
