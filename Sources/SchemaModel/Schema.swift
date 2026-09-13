import Foundation

public struct AnalysisStats: Hashable, Sendable, Codable {
    public var fullyParsedObjects: Int
    public var partiallyParsedObjects: Int
    /// Statements the parser recognized but doesn't fully support yet.
    /// A truly "unsupported" statement — the parser saw something it
    /// couldn't interpret.
    public var skippedStatements: Int
    /// Statements the parser intentionally ignores because they don't
    /// describe schema: `BEGIN` / `COMMIT` / `ROLLBACK`, DML like
    /// `SELECT` / `INSERT`, session `SET`, `GRANT` / `REVOKE`, etc.
    /// These are not errors — they simply have no schema footprint.
    public var ignoredStatements: Int

    public init(
        fullyParsedObjects: Int = 0,
        partiallyParsedObjects: Int = 0,
        skippedStatements: Int = 0,
        ignoredStatements: Int = 0
    ) {
        self.fullyParsedObjects = fullyParsedObjects
        self.partiallyParsedObjects = partiallyParsedObjects
        self.skippedStatements = skippedStatements
        self.ignoredStatements = ignoredStatements
    }
}

public struct Schema: Sendable, Codable {
    public var tables: [Identifier: Table]
    public var views: [Identifier: View]
    public var triggers: [Identifier: Trigger]
    public var routines: [Identifier: Routine]
    public var dialect: Dialect
    public var diagnostics: [Diagnostic]
    public var stats: AnalysisStats

    public init(
        tables: [Identifier: Table] = [:],
        views: [Identifier: View] = [:],
        triggers: [Identifier: Trigger] = [:],
        routines: [Identifier: Routine] = [:],
        dialect: Dialect = .unknown,
        diagnostics: [Diagnostic] = [],
        stats: AnalysisStats = AnalysisStats()
    ) {
        self.tables = tables
        self.views = views
        self.triggers = triggers
        self.routines = routines
        self.dialect = dialect
        self.diagnostics = diagnostics
        self.stats = stats
    }

    /// Human-readable analysis summary. The wording matches the spec's
    /// example, with an appended clause when non-schema DML/transaction
    /// statements were ignored (so users understand `BEGIN;`/`COMMIT;`/
    /// `SELECT` aren't errors).
    public var summarySentence: String {
        var parts: [String] = []
        parts.append("Found \(tables.count) tables, \(views.count) views, and \(routines.count) functions.")
        parts.append("Fully parsed \(stats.fullyParsedObjects) objects, partially parsed \(stats.partiallyParsedObjects) objects, and skipped \(stats.skippedStatements) unsupported statements.")
        if stats.ignoredStatements > 0 {
            parts.append("Ignored \(stats.ignoredStatements) non-schema statements (transaction / DML / session).")
        }
        return parts.joined(separator: " ")
    }
}
