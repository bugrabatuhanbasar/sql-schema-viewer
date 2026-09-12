# Mac SQL Schema Viewer

A lightweight, fully offline macOS application that visualizes schemas and
object dependencies from SQL and DBML files without uploading them anywhere.

> Your schema never leaves your Mac. No network, no account, no telemetry.

See [mac-sql-schema-viewer.md](mac-sql-schema-viewer.md) for the full product
specification.

## Status

Milestone **M5 — Oracle parser** (M1–M4 also complete). On top of M1's
foundations and M2's PostgreSQL vertical slice + SwiftUI app, the MySQL /
MariaDB parser is now in place (`CREATE TABLE` with backticks, engine
trailers, `AUTO_INCREMENT`, table/column FKs; `ALTER TABLE`; `CREATE
INDEX`; view/trigger/routine headers), plus an expanded dialect detector
and its unit tests. Fault-tolerant parsing is formalized: one malformed
statement never discards the rest of the file. Xcode app setup is
documented in [App/README.md](App/README.md).

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
