# Mac SQL Schema Viewer

A lightweight, fully offline macOS application that visualizes schemas and
object dependencies from SQL and DBML files without uploading them anywhere.

> Your schema never leaves your Mac. No network, no account, no telemetry.

See [mac-sql-schema-viewer.md](mac-sql-schema-viewer.md) for the full product
specification.

## Status

Milestone **M1 — Foundations**. The Swift Package Manager workspace, the
normalized schema model, the shared lexer/splitter, and the network-guard
tests are in place. Per-dialect parsers, the diagram renderer, and the
SwiftUI app come in later milestones.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (Swift 5.9+)

## Building and testing

Everything runs from the command line, fully offline:

```
swift build
swift test
```

The `NetworkGuardTests` target asserts that no first-party code links against
`URLSession`, `Network.framework`, or `CFNetwork`.

## Repository layout

```
Sources/
  SchemaModel/         Normalized intermediate representation (tables, columns,
                       constraints, indexes, views, triggers, routines,
                       references, diagnostics).
  SQLLexer/            Dialect-parameterized tokenizer with source-range tracking.
  ParserCore/          Statement splitter, panic-mode recovery, parser protocols.
  PostgresParser/      (M2)
  MySQLParser/         (M3) MariaDB shares this target via a dialect flag.
  SQLiteParser/        (M4)
  OracleParser/        (M5)
  DBMLParser/          (M6) DBML import + serializer.
  DialectDetector/     Heuristic dialect detection.
  DependencyAnalyzer/  View / trigger / function / procedure dependency graph.
  QualityChecks/       V1 schema-quality checks.
  LayoutEngine/        Layered + force-directed diagram layout.
  DiagramRenderer/     Core Graphics scene, PNG / SVG / PDF exporters.
  MermaidExporter/     Mermaid ER diagram text emitter.
  SchemaKit/           Umbrella facade consumed by both app and CLI.
  SchemaViewerCLI/     `schema-viewer` executable.
Tests/
  ...
```

## macOS app target

The SwiftUI application shell is added in milestone M2 as an Xcode project
under `App/MacSQLSchemaViewer.xcodeproj`. It links the SPM package
`SchemaKit`. Bundle identifier: `org.macsqlschemaviewer.MacSQLSchemaViewer`.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
