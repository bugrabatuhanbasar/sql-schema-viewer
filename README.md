# Mac SQL Schema Viewer

A lightweight, fully offline macOS application that visualizes schemas and
object dependencies from SQL and DBML files without uploading them anywhere.

> Your schema never leaves your Mac. No network, no account, no telemetry.

See [mac-sql-schema-viewer.md](mac-sql-schema-viewer.md) for the full product
specification.

## Status

**Version 1 feature-complete.** All spec §V1 acceptance criteria are in
place. See the checklist below.

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
`URLSession`, `Network.framework`, or `CFNetwork`. There are **zero**
third-party runtime dependencies.

## The CLI

```
swift build -c release
.build/release/schema-viewer inspect schema.sql
.build/release/schema-viewer check schema.sql
.build/release/schema-viewer render schema.sql --output schema.svg
.build/release/schema-viewer export schema.sql --format dbml --output schema.dbml
```

Full help: `schema-viewer help`.

Exit codes:
- `0` success
- `1` quality-check warnings surfaced
- `2` parser errors surfaced
- `64` usage error
- `74` I/O error

## The macOS app

The SwiftUI application lives under [App/](App/). See
[App/README.md](App/README.md) for the one-time Xcode project setup steps.

Bundle identifier: `org.macsqlschemaviewer.MacSQLSchemaViewer`. Sandbox on;
only user-selected read/write is granted; **no network entitlements are ever
declared**.

## Repository layout

```
Sources/
  SchemaModel/         Normalized intermediate representation.
  SQLLexer/            Dialect-parameterized tokenizer.
  ParserCore/          Statement splitter, panic-mode recovery, protocols.
  PostgresParser/      CREATE / ALTER TABLE, CREATE INDEX, COMMENT, view /
                       trigger / routine headers.
  MySQLParser/         MySQL + MariaDB (shared target, flavor flag).
  SQLiteParser/        Affinity-typed CREATE TABLE, WITHOUT ROWID,
                       AUTOINCREMENT.
  OracleParser/        NUMBER / VARCHAR2 / DATE / PL-SQL headers as .partial.
  DBMLParser/          DBML import + serializer.
  DialectDetector/     Heuristic dialect detection.
  DependencyAnalyzer/  FK edges + body-scan for view/trigger/routine.
  QualityChecks/       9 checks per spec §11.
  LayoutEngine/        Layered longest-path layout.
  DiagramRenderer/     DiagramScene + SVG serializer + PNG/PDF via CG.
  MermaidExporter/     Mermaid ER text emitter.
  SchemaKit/           Umbrella facade consumed by app and CLI.
  AppUI/               SwiftUI three-pane document window with CG canvas.
  SchemaViewerCLI/     schema-viewer executable.
```

## V1 Acceptance Criteria (spec §V1)

- [x] Opens PostgreSQL, MySQL, SQLite, MariaDB, and Oracle DDL files.
- [x] Imports and exports DBML.
- [x] Displays tables, columns, keys, constraints, indexes, and
      relationships.
- [x] Displays view and materialized-view dependencies.
- [x] Displays detectable trigger, function, and procedure dependencies
      (dynamic-SQL references marked `.partial`).
- [x] Continues parsing the rest of a file after encountering an invalid
      statement (per-slice isolation + panic-mode recovery).
- [x] Performs the basic schema-quality checks defined in §11.
- [x] Exports PNG, SVG, PDF, Mermaid, and DBML.
- [x] Includes a local CLI that uses the same analysis engine as the GUI.
- [x] Never executes SQL.
- [x] Never connects to a database or internet service — enforced by
      `NetworkGuardTests`, no network entitlement, and zero third-party
      runtime dependencies.
- [x] Usable performance for a schema of at least 200 tables (perf test
      in `PostgresParserTests` parses 200 tables well under 2 s).

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
