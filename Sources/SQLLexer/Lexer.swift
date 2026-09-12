import Foundation
import SchemaModel

/// A single-pass, byte-oriented SQL lexer. Never throws; unknown bytes become
/// `.unknown` tokens so the parser can decide how to recover.
public struct Lexer: Sendable {
    public let buffer: SourceBuffer
    public let config: LexerConfig
    private let bytes: [UInt8]

    public init(_ buffer: SourceBuffer, config: LexerConfig) {
        self.buffer = buffer
        self.config = config
        self.bytes = buffer.bytes
    }

    public func tokenize(skippingTrivia: Bool = true) -> [Token] {
        var out: [Token] = []
        var i = 0
        while i < bytes.count {
            let start = i
            let b = bytes[i]

            // Whitespace
            if isWhitespace(b) {
                while i < bytes.count && isWhitespace(bytes[i]) { i += 1 }
                if !skippingTrivia { out.append(makeToken(.whitespace, start: start, end: i)) }
                continue
            }

            // -- line comment
            if config.supportsDoubleDashComments, b == 0x2D, i + 1 < bytes.count, bytes[i + 1] == 0x2D {
                while i < bytes.count && bytes[i] != 0x0A { i += 1 }
                if !skippingTrivia { out.append(makeToken(.lineComment, start: start, end: i)) }
                continue
            }

            // # line comment (MySQL/MariaDB)
            if config.supportsHashComments, b == 0x23 {
                while i < bytes.count && bytes[i] != 0x0A { i += 1 }
                if !skippingTrivia { out.append(makeToken(.lineComment, start: start, end: i)) }
                continue
            }

            // /* block comment */ — nesting allowed only in Postgres,
            // but we accept nesting universally (harmless for others).
            if b == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2A {
                i += 2
                var depth = 1
                while i < bytes.count && depth > 0 {
                    if bytes[i] == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2A {
                        depth += 1; i += 2
                    } else if bytes[i] == 0x2A, i + 1 < bytes.count, bytes[i + 1] == 0x2F {
                        depth -= 1; i += 2
                    } else {
                        i += 1
                    }
                }
                if !skippingTrivia { out.append(makeToken(.blockComment, start: start, end: i)) }
                continue
            }

            // 'string literal' with '' escapes
            if b == 0x27 {
                i += 1
                while i < bytes.count {
                    if bytes[i] == 0x27 {
                        if i + 1 < bytes.count && bytes[i + 1] == 0x27 { i += 2; continue }
                        i += 1; break
                    }
                    i += 1
                }
                out.append(makeToken(.stringLiteral, start: start, end: i))
                continue
            }

            // Postgres dollar-quoted string
            if config.supportsDollarQuoting, b == 0x24 {
                if let (endIndex, tokenEnd) = scanDollarQuote(from: i) {
                    _ = endIndex
                    out.append(makeToken(.dollarQuotedString, start: start, end: tokenEnd))
                    i = tokenEnd
                    continue
                }
                // Fall through: treat $ as punctuation/unknown
            }

            // Quoted identifier
            if b == config.identifierQuote || (config.alternateIdentifierQuote != nil && b == config.alternateIdentifierQuote!) {
                let quote = b
                i += 1
                while i < bytes.count {
                    if bytes[i] == quote {
                        if i + 1 < bytes.count && bytes[i + 1] == quote { i += 2; continue }
                        i += 1; break
                    }
                    i += 1
                }
                out.append(makeToken(.quotedIdentifier, start: start, end: i))
                continue
            }

            // Identifier / keyword
            if isIdentifierStart(b) {
                i += 1
                while i < bytes.count && isIdentifierContinue(bytes[i]) { i += 1 }
                let raw = slice(start, i)
                let upper = raw.uppercased()
                if config.keywords.contains(upper) {
                    out.append(Token(kind: .keyword(upper), byteOffset: start, byteLength: i - start, text: raw))
                } else {
                    out.append(Token(kind: .identifier, byteOffset: start, byteLength: i - start, text: raw))
                }
                continue
            }

            // Number
            if isDigit(b) || (b == 0x2E && i + 1 < bytes.count && isDigit(bytes[i + 1])) {
                while i < bytes.count && (isDigit(bytes[i]) || bytes[i] == 0x2E) { i += 1 }
                // exponent
                if i < bytes.count, bytes[i] == 0x65 || bytes[i] == 0x45 {
                    i += 1
                    if i < bytes.count, bytes[i] == 0x2B || bytes[i] == 0x2D { i += 1 }
                    while i < bytes.count && isDigit(bytes[i]) { i += 1 }
                }
                out.append(makeToken(.number, start: start, end: i))
                continue
            }

            // Multi-char operators
            if let (op, len) = scanOperator(at: i) {
                i += len
                out.append(Token(kind: .operator(op), byteOffset: start, byteLength: len, text: op))
                continue
            }

            // Single-char punctuation
            if isPunctuation(b) {
                i += 1
                out.append(Token(kind: .punctuation(b), byteOffset: start, byteLength: 1, text: String(UnicodeScalar(b))))
                continue
            }

            // Unknown byte — advance one and record it so we make progress
            i += 1
            out.append(makeToken(.unknown, start: start, end: i))
        }
        out.append(Token(kind: .endOfFile, byteOffset: bytes.count, byteLength: 0, text: ""))
        return out
    }

    // MARK: helpers

    private func slice(_ start: Int, _ end: Int) -> String {
        let sub = bytes[start..<end]
        return String(decoding: sub, as: UTF8.self)
    }

    private func makeToken(_ kind: TokenKind, start: Int, end: Int) -> Token {
        Token(kind: kind, byteOffset: start, byteLength: end - start, text: slice(start, end))
    }

    private func isWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D || b == 0x0B || b == 0x0C
    }
    private func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    private func isAlpha(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
    }
    private func isIdentifierStart(_ b: UInt8) -> Bool {
        isAlpha(b) || b == 0x5F || b >= 0x80
    }
    private func isIdentifierContinue(_ b: UInt8) -> Bool {
        isAlpha(b) || isDigit(b) || b == 0x5F || b == 0x24 || b >= 0x80
    }
    private func isPunctuation(_ b: UInt8) -> Bool {
        switch b {
        case 0x28, 0x29, 0x2C, 0x3B, 0x2E, 0x2A, 0x2B, 0x2D, 0x2F, 0x25, 0x5B, 0x5D, 0x7B, 0x7D, 0x3D, 0x3C, 0x3E, 0x21, 0x7C, 0x26, 0x5E, 0x7E, 0x3F, 0x40, 0x3A:
            return true
        default:
            return false
        }
    }

    private func scanOperator(at i: Int) -> (String, Int)? {
        // Ordered longest-first
        let candidates: [String] = ["->>", "->", "::", ":=", "<=", ">=", "<>", "!=", "||", "&&", ".."]
        for c in candidates {
            let cbytes = Array(c.utf8)
            if i + cbytes.count <= bytes.count {
                var match = true
                for k in 0..<cbytes.count where bytes[i + k] != cbytes[k] { match = false; break }
                if match { return (c, cbytes.count) }
            }
        }
        return nil
    }

    /// Returns (endOfClosingTagInclusive, tokenEndExclusive) if a valid
    /// dollar-quoted string is present starting at `i` (a `$`). Otherwise nil.
    private func scanDollarQuote(from i: Int) -> (Int, Int)? {
        // Read optional tag: $tag$ … $tag$
        // Tag characters are identifier chars excluding '$'.
        var j = i + 1
        let tagStart = j
        while j < bytes.count {
            let c = bytes[j]
            if c == 0x24 { break }
            if isAlpha(c) || isDigit(c) || c == 0x5F || c >= 0x80 { j += 1 } else { break }
        }
        guard j < bytes.count, bytes[j] == 0x24 else { return nil }
        let tagBytes = Array(bytes[tagStart..<j])
        let closingLen = tagBytes.count + 2 // $ + tag + $
        let bodyStart = j + 1
        var k = bodyStart
        while k < bytes.count {
            if bytes[k] == 0x24 {
                // check closing
                if k + closingLen - 1 < bytes.count {
                    var match = bytes[k] == 0x24
                    if match {
                        for t in 0..<tagBytes.count {
                            if bytes[k + 1 + t] != tagBytes[t] { match = false; break }
                        }
                    }
                    if match, bytes[k + 1 + tagBytes.count] == 0x24 {
                        return (k + closingLen - 1, k + closingLen)
                    }
                }
            }
            k += 1
        }
        return nil // unterminated
    }
}
