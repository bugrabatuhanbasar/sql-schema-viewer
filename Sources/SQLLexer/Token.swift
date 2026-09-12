import Foundation
import SchemaModel

public enum TokenKind: Sendable, Equatable {
    case identifier         // unquoted
    case quotedIdentifier   // "foo", `foo`, [foo]
    case keyword(String)    // uppercased form
    case number
    case stringLiteral
    case dollarQuotedString // Postgres $tag$…$tag$
    case punctuation(UInt8) // single-byte: ( ) , ; . *
    case `operator`(String) // multi-char: :=, ->, ->>, ::, etc.
    case lineComment
    case blockComment
    case whitespace
    case endOfFile
    case unknown
}

public struct Token: Sendable, Equatable {
    public var kind: TokenKind
    public var byteOffset: Int
    public var byteLength: Int
    public var text: String   // raw slice as UTF-8 string

    public init(kind: TokenKind, byteOffset: Int, byteLength: Int, text: String) {
        self.kind = kind
        self.byteOffset = byteOffset
        self.byteLength = byteLength
        self.text = text
    }

    public func sourceRange(file: URL?, using index: LineIndex) -> SourceRange {
        let start = index.position(atByteOffset: byteOffset)
        let end = index.position(atByteOffset: byteOffset + byteLength)
        return SourceRange(
            file: file,
            startLine: start.line, startColumn: start.column,
            endLine: end.line, endColumn: end.column,
            byteOffset: byteOffset, byteLength: byteLength
        )
    }
}
