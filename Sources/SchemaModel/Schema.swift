import Foundation

public struct AnalysisStats: Hashable, Sendable, Codable {
    public var fullyParsedObjects: Int
    public var partiallyParsedObjects: Int
    public var skippedStatements: Int

    public init(fullyParsedObjects: Int = 0, partiallyParsedObjects: Int = 0, skippedStatements: Int = 0) {
        self.fullyParsedObjects = fullyParsedObjects
        self.partiallyParsedObjects = partiallyParsedObjects
        self.skippedStatements = skippedStatements
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

    /// Human-readable analysis summary matching the spec's example wording.
    public var summarySentence: String {
        let objectCount = tables.count + views.count + routines.count + triggers.count
        var parts: [String] = []
        parts.append("Found \(tables.count) tables, \(views.count) views, and \(routines.count) functions.")
        parts.append("Fully parsed \(stats.fullyParsedObjects) objects, partially parsed \(stats.partiallyParsedObjects) objects, and skipped \(stats.skippedStatements) unsupported statements.")
        _ = objectCount
        return parts.joined(separator: " ")
    }
}
