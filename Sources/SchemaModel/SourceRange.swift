import Foundation

public struct SourceRange: Hashable, Sendable, Codable {
    public var file: URL?
    public var startLine: Int
    public var startColumn: Int
    public var endLine: Int
    public var endColumn: Int
    public var byteOffset: Int
    public var byteLength: Int

    public init(
        file: URL? = nil,
        startLine: Int,
        startColumn: Int,
        endLine: Int,
        endColumn: Int,
        byteOffset: Int,
        byteLength: Int
    ) {
        self.file = file
        self.startLine = startLine
        self.startColumn = startColumn
        self.endLine = endLine
        self.endColumn = endColumn
        self.byteOffset = byteOffset
        self.byteLength = byteLength
    }

    public static let zero = SourceRange(
        startLine: 0, startColumn: 0,
        endLine: 0, endColumn: 0,
        byteOffset: 0, byteLength: 0
    )
}
