import Foundation
import SchemaModel
import SQLLexer

/// One logical top-level statement extracted by the splitter. The slice
/// carries the raw byte range and a snapshot of the tokens so a dialect
/// parser can consume it in isolation. If parsing the slice fails, the
/// remainder of the file is unaffected — that is the core fault-tolerance
/// contract.
public struct StatementSlice: Sendable {
    public let byteOffset: Int
    public let byteLength: Int
    public let text: String
    public let tokens: [Token]

    public init(byteOffset: Int, byteLength: Int, text: String, tokens: [Token]) {
        self.byteOffset = byteOffset
        self.byteLength = byteLength
        self.text = text
        self.tokens = tokens
    }
}
