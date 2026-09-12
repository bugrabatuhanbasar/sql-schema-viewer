# Mac SQL Schema Viewer

A lightweight, fully offline macOS application that visualizes schemas and
object dependencies from SQL and DBML files without uploading them anywhere.

> Your schema never leaves your Mac. No network, no account, no telemetry.

See [mac-sql-schema-viewer.md](mac-sql-schema-viewer.md) for the full product
specification.

## Status

Milestone **M2 — PostgreSQL vertical slice**. On top of M1's foundations,
the PostgreSQL DDL recognizer (`CREATE TABLE`, `ALTER TABLE`, `CREATE INDEX`,
`COMMENT ON`, plus view/routine/trigger headers), the layered layout engine,
the SwiftUI three-pane document window, and the Core-Graphics diagram canvas
are now in place. Xcode app setup is documented in [App/README.md](App/README.md).

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

The SwiftUI application lives under [App/](App/). See
[App/README.md](App/README.md) for the one-time Xcode project setup steps.
Bundle identifier: `org.macsqlschemaviewer.MacSQLSchemaViewer`.
Sandbox is on; only user-selected read/write is granted; no network
entitlements are ever declared.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
