import Foundation

public enum DiagnosticSeverity: String, Sendable, Codable {
    case error
    case warning
    case info
}

public struct Diagnostic: Hashable, Sendable, Codable {
    public var severity: DiagnosticSeverity
    public var code: String
    public var message: String
    public var source: SourceRange
    public var hint: String?

    public init(
        severity: DiagnosticSeverity,
        code: String,
        message: String,
        source: SourceRange = .zero,
        hint: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.source = source
        self.hint = hint
    }
}
