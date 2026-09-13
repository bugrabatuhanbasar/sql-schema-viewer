import Foundation
@_exported import SchemaModel
@_exported import ParserCore
@_exported import LayoutEngine
@_exported import DiagramRenderer
@_exported import DependencyAnalyzer
import PostgresParser
import MySQLParser
import SQLiteParser
import OracleParser
import DBMLParser
import DialectDetector
import QualityChecks
import MermaidExporter

/// The umbrella API consumed by both the SwiftUI app and the CLI. Any
/// feature parity between GUI and CLI is enforced by routing both through
/// this facade.
public enum SchemaKit {

    /// Analyze a file's contents. Optional override forces a specific
    /// dialect; otherwise `DialectDetector` decides.
    public static func analyze(
        contents: String,
        file: URL? = nil,
        dialectOverride: Dialect? = nil
    ) -> ParseResult<Schema> {
        let dialect = dialectOverride ?? DialectDetector.detect(fromContents: contents, filename: file?.lastPathComponent)
        let parser: any StatementParser
        switch dialect {
        case .postgres: parser = PostgresParser()
        case .mysql:    parser = MySQLParser(flavor: .mysql)
        case .mariadb:  parser = MySQLParser(flavor: .mariadb)
        case .sqlite:   parser = SQLiteParser()
        case .oracle:   parser = OracleParser()
        case .dbml:     parser = DBMLParser()
        case .unknown:  parser = PostgresParser() // best-effort default
        }
        var result = parser.parse(source: contents, file: file)
        let qualityDiags = QualityChecks.run(on: result.value)
        result.value.diagnostics.append(contentsOf: qualityDiags)
        result.diagnostics.append(contentsOf: qualityDiags)
        return result
    }

    /// Convenience: analyze a file from disk. No network use — reads the
    /// local filesystem only.
    public static func analyzeFile(at url: URL, dialectOverride: Dialect? = nil) throws -> ParseResult<Schema> {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        return analyze(contents: text, file: url, dialectOverride: dialectOverride)
    }

    public static func mermaid(from schema: Schema) -> String {
        MermaidExporter.export(schema)
    }

    public static func dbml(from schema: Schema) -> String {
        DBMLExporter.export(schema).value
    }

    public static func dependencyGraph(from schema: Schema) -> DependencyGraph {
        DependencyAnalyzer.analyze(schema)
    }

    public static func layout(_ schema: Schema) -> LayoutResult {
        LayoutEngine.layout(schema)
    }

    public static func scene(from schema: Schema) -> DiagramScene {
        DiagramRenderer.buildScene(schema, layout: LayoutEngine.layout(schema))
    }

    public static func svg(from schema: Schema) -> String {
        SVGExporter.export(scene(from: schema))
    }

    #if canImport(AppKit)
    public static func png(from schema: Schema) -> Data? {
        RasterExporter.png(scene(from: schema))
    }
    public static func pdf(from schema: Schema) -> Data? {
        RasterExporter.pdf(scene(from: schema))
    }
    #endif
}
