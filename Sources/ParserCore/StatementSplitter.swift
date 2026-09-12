import Foundation
import SchemaModel
import SQLLexer

/// Splits a source buffer into top-level statements without invoking a full
/// grammar. Delimiters:
///   - `;` at paren depth 0 outside strings/comments
///   - MySQL/MariaDB `DELIMITER $$` … `$$` (recognized as a keyword-run at
///     line start; delimiter is scanned raw)
///   - Oracle `/` on its own line ends a PL/SQL block
///
/// Balanced parentheses and dollar-quoted / string-quoted regions are
/// respected via the lexer's tokenization.
public struct StatementSplitter: Sendable {
    public let config: LexerConfig

    public init(config: LexerConfig) {
        self.config = config
    }

    public func split(_ buffer: SourceBuffer) -> [StatementSlice] {
        let lexer = Lexer(buffer, config: config)
        let allTokens = lexer.tokenize(skippingTrivia: true)

        var slices: [StatementSlice] = []
        var current: [Token] = []
        var parenDepth = 0
        var sliceStart: Int? = nil

        func flush(endByteExclusive: Int) {
            guard let start = sliceStart else { return }
            // Trim trailing empty slice.
            let nonTrivial = current.contains { token in
                switch token.kind {
                case .whitespace, .lineComment, .blockComment: return false
                default: return true
                }
            }
            if nonTrivial {
                let length = max(0, endByteExclusive - start)
                let text = String(decoding: buffer.bytes[start..<start + length], as: UTF8.self)
                slices.append(StatementSlice(
                    byteOffset: start,
                    byteLength: length,
                    text: text,
                    tokens: current
                ))
            }
            current.removeAll(keepingCapacity: true)
            sliceStart = nil
        }

        for token in allTokens {
            switch token.kind {
            case .endOfFile:
                flush(endByteExclusive: token.byteOffset)
            case .punctuation(let b):
                if b == 0x28 { parenDepth += 1 }
                else if b == 0x29 { parenDepth = max(0, parenDepth - 1) }
                if b == 0x3B && parenDepth == 0 {
                    // include the semicolon in the slice for source range
                    if sliceStart == nil { sliceStart = token.byteOffset }
                    current.append(token)
                    flush(endByteExclusive: token.byteOffset + token.byteLength)
                    continue
                }
                if sliceStart == nil { sliceStart = token.byteOffset }
                current.append(token)
            case .keyword, .identifier, .quotedIdentifier, .number,
                 .stringLiteral, .dollarQuotedString, .operator, .unknown,
                 .whitespace, .lineComment, .blockComment:
                if sliceStart == nil { sliceStart = token.byteOffset }
                current.append(token)
            }
        }
        return slices
    }
}
