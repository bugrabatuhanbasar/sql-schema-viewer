# Mac SQL Schema Viewer

## Product Definition

Mac SQL Schema Viewer is a lightweight native macOS application that analyzes
`.sql`, `.ddl`, and `.dbml` files without uploading them to a server. It
visualizes database schemas and dependencies between database objects.

The application runs entirely on the user's device. It never executes SQL,
connects to a database, or transmits schema data over the internet.

> Your schema never leaves your Mac. No network, no account, no telemetry.

---

## Core Product Principles

- Native macOS desktop application
- Fully functional without an internet connection
- No outgoing network requests
- No user accounts or authentication
- No cloud storage or synchronization
- No online sharing
- No telemetry, analytics, advertising, or automatic crash reporting
- Never execute SQL statements
- Never connect to a database server
- Fast startup with low CPU and memory usage
- Open-source code and transparent dependencies

These principles apply to the product as a whole, not only to its first release.

---

## Version 1 Scope

### 1. Opening Files

- Open `.sql`, `.ddl`, and `.dbml` files
- Open supported files by double-clicking them in Finder
- Drag and drop files into the application window
- Paste SQL or DBML content from the clipboard
- Display recently opened files
- Support UTF-8 and common text encodings
- Refresh the diagram when the source file changes

### 2. Supported SQL Dialects

Version 1 will support:

- PostgreSQL
- MySQL
- SQLite
- MariaDB
- Oracle

The application will attempt to detect the SQL dialect automatically. Users
must be able to override the detected dialect.

### 3. SQL Schema Analysis

The application will parse the following definitions where supported by the
selected dialect:

- `CREATE TABLE`
- `ALTER TABLE`
- Column names and data types
- Primary keys
- Composite primary keys
- Foreign keys
- Composite foreign keys
- Unique constraints
- Not-null constraints
- Default values
- Check constraints
- Single-column and multi-column indexes
- Table and column comments

Data manipulation statements such as `INSERT`, `UPDATE`, and `DELETE` will
never be executed. Content that is unnecessary for schema visualization will
be safely ignored.

### 4. DBML Import and Export

- Open DBML files
- Paste DBML from the clipboard
- Convert DBML into a visual diagram
- Export a parsed SQL schema as DBML
- Report transformations that cannot preserve every detail
- Show unsupported DBML statements with line numbers

### 5. Table and Relationship Diagram

- Display tables as diagram nodes
- Display column names and data types
- Identify primary-key and foreign-key columns with icons
- Draw foreign-key relationships
- Distinguish one-to-one and one-to-many relationships
- Automatically arrange the diagram
- Allow tables to be repositioned manually
- Support zooming and panning
- Fit the entire diagram to the window
- Support light and dark appearance
- Highlight the selected table and its direct relationships

### 6. Views and Materialized Views

- Display regular views
- Display materialized views with a distinct icon
- Connect a view to the tables it uses
- Connect a view to other views it uses
- Display the view definition in the details panel
- Mark detected dependencies as complete or partial

### 7. Trigger, Function, and Procedure Dependencies

- Display triggers and their associated tables
- List functions
- List procedures
- Detect explicit table usage inside functions and procedures
- Show tables read or modified by a trigger when reliably detectable
- Mark dependencies affected by dynamic SQL as partial
- Use distinct icons for tables, views, triggers, functions, and procedures

This is static schema analysis, not a SQL execution engine or a complete data
lineage platform. Only dependencies that can be extracted reliably from the
source files will be displayed.

### 8. Search and Filtering

- Search by table, view, column, trigger, function, or procedure name
- Focus the diagram on a search result
- Show only the selected object and its direct dependencies
- Filter by database-object type
- Filter tables that have no relationships

### 9. Details Panel

Depending on the selected object, display:

- Object name and type
- Columns and data types
- Primary and foreign keys
- Indexes
- Unique and check constraints
- Incoming and outgoing dependencies
- View definition
- Trigger, function, or procedure definition
- Source file and line number

### 10. Fault-Tolerant Parsing

- Do not stop the entire analysis because of one invalid statement
- Skip an unsupported statement and continue parsing the remaining schema
- Report errors with file and line information
- Report unsupported SQL features as warnings
- Distinguish completely and partially parsed objects
- Display a concise analysis summary

Example:

> Found 24 tables, 3 views, and 6 functions. Fully parsed 30 objects, partially parsed 3 objects, and skipped 4 unsupported statements.

### 11. Schema Quality Checks

Version 1 will include the following basic checks:

- Tables without primary keys
- Foreign-key pairs with incompatible data types
- Foreign-key columns without indexes
- Columns such as `*_id` that are not connected by a foreign key
- Duplicate table or column names in the same scope
- Tables without relationships
- Missing or unparsed constraints
- Possible circular dependencies
- References to nonexistent tables or columns

Quality checks only produce warnings. The application will never modify the
source SQL automatically. Each warning should navigate to the relevant object
and source line when possible.

### 12. Export

- PNG
- True vector SVG
- PDF
- Mermaid ER diagram
- DBML

All exports are generated locally.

### 13. Command-Line Interface

Version 1 will include a local CLI using the same parser and analysis engine as
the graphical application.

Example commands:

```bash
schema-viewer inspect schema.sql
schema-viewer check schema.sql
schema-viewer render schema.sql --output schema.svg
schema-viewer export schema.sql --format dbml
```

The CLI must:

- Work without an internet connection
- Detect the SQL dialect automatically or accept it as an argument
- Print analysis results in the terminal
- Return meaningful exit codes for parse errors and quality warnings
- Generate PNG, SVG, PDF, Mermaid, and DBML output
- Work in local scripts and CI environments
- Never connect to a cloud service

---

## Interface Structure

### Welcome Screen

- **Open SQL or DBML File** button
- Drag-and-drop area
- **Paste from Clipboard** action
- Recently opened files

### Main Window

- Left sidebar: object list, search, and filters
- Center: schema and dependency diagram
- Right sidebar: selected-object details
- Bottom panel: parser errors and schema-quality warnings
- Toolbar: open, refresh, auto-layout, fit to window, and export

---

## Basic User Flow

1. The user opens a `.sql`, `.ddl`, or `.dbml` file.
2. The application detects the SQL dialect when applicable.
3. The file is analyzed in the background without executing any statement.
4. Tables, views, programmable objects, and dependencies are displayed.
5. Parse problems and schema-quality warnings are listed.
6. The user searches, filters, and inspects objects.
7. The user optionally exports the diagram or schema to a local file.

---

## Features That Will Not Be Included

- User accounts or authentication
- Cloud storage
- Cloud synchronization between devices
- Online sharing or share links
- Real-time collaboration
- Internet-based AI assistants
- Telemetry or analytics
- Database connections
- SQL query execution
- Viewing or editing database data
- Team, role, or permission management

These features conflict with the application's offline and privacy-first model
and are not planned for future releases.

---

## Features That May Be Added Later

- Microsoft SQL Server support
- Schema-to-schema comparison
- Sequential analysis of migration directories
- Inference of undeclared relationships from column names
- Finder Quick Look previews
- A specialized performance mode for schemas with thousands of tables

---

## Technical Direction

- User interface: SwiftUI
- Native macOS integrations where necessary: AppKit
- Diagram rendering: an optimized Core Graphics-based canvas
- Background analysis: Swift Concurrency
- Document model: `DocumentGroup` or `NSDocument`
- Separate parser, schema model, GUI, and CLI modules
- One common intermediate schema model for all SQL dialects
- The GUI and CLI must use the same parser and quality-check engine
- Automated tests must run without network access

---

## Version 1 Acceptance Criteria

Version 1 is complete when it:

- Opens PostgreSQL, MySQL, SQLite, MariaDB, and Oracle DDL files.
- Imports and exports DBML.
- Displays tables, columns, keys, constraints, indexes, and relationships.
- Displays view and materialized-view dependencies.
- Displays detectable trigger, function, and procedure dependencies.
- Continues parsing the rest of a file after encountering an invalid statement.
- Performs the basic schema-quality checks defined above.
- Exports PNG, SVG, PDF, Mermaid, and DBML.
- Includes a local CLI that uses the same analysis engine as the GUI.
- Never executes SQL.
- Never connects to a database or internet service.
- Provides usable performance for a reasonable schema of at least 200 tables.

---

## Suggested Implementation Order

1. Common schema and dependency model
2. PostgreSQL parser
3. Basic native macOS interface
4. Table diagram and foreign-key connections
5. File opening, Finder integration, and drag and drop
6. Fault-tolerant parsing infrastructure
7. MySQL and MariaDB parsers
8. SQLite parser
9. Oracle parser
10. DBML import and export
11. View and materialized-view support
12. Trigger, function, and procedure dependencies
13. Search, filtering, and details panel
14. Schema-quality checks
15. PNG, SVG, PDF, and Mermaid export
16. CLI
17. Performance, security, and parser compatibility tests
18. First open-source release

---

## One-Sentence Product Description

**A lightweight, fully offline macOS application that visualizes schemas and
object dependencies from SQL and DBML files without uploading them anywhere.**
