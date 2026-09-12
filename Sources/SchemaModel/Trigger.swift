import Foundation

public enum TriggerTiming: String, Sendable, Codable {
    case before
    case after
    case insteadOf
    case unknown
}

public enum TriggerEvent: String, Sendable, Codable {
    case insert
    case update
    case delete
    case truncate
}

public struct Trigger: Hashable, Sendable, Codable, Identifiable {
    public var id: String { name.normalized }
    public var name: Identifier
    public var table: Identifier
    public var timing: TriggerTiming
    public var events: [TriggerEvent]
    public var bodySQL: String
    public var tablesRead: [Reference]
    public var tablesWritten: [Reference]
    public var source: SourceRange
    public var confidence: ParseConfidence

    public init(
        name: Identifier,
        table: Identifier,
        timing: TriggerTiming = .unknown,
        events: [TriggerEvent] = [],
        bodySQL: String = "",
        tablesRead: [Reference] = [],
        tablesWritten: [Reference] = [],
        source: SourceRange = .zero,
        confidence: ParseConfidence = .complete
    ) {
        self.name = name
        self.table = table
        self.timing = timing
        self.events = events
        self.bodySQL = bodySQL
        self.tablesRead = tablesRead
        self.tablesWritten = tablesWritten
        self.source = source
        self.confidence = confidence
    }
}
