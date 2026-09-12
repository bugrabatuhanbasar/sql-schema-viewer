import Foundation
import SchemaModel
import SQLLexer

/// A random-access cursor over a token stream with panic-mode recovery
/// primitives. Non-throwing by design: parsers inspect `error` after a
/// recovery attempt.
public struct TokenCursor {
    public let tokens: [Token]
    public let file: URL?
    public let lineIndex: LineIndex
    public var index: Int = 0

    public init(tokens: [Token], file: URL?, lineIndex: LineIndex) {
        self.tokens = tokens
        self.file = file
        self.lineIndex = lineIndex
    }

    public var isAtEnd: Bool {
        if index >= tokens.count { return true }
        if case .endOfFile = tokens[index].kind { return true }
        return false
    }

    public var current: Token { tokens[index] }

    public func peek(_ offset: Int = 1) -> Token? {
        let j = index + offset
        return j < tokens.count ? tokens[j] : nil
    }

    @discardableResult
    public mutating func advance() -> Token {
        let t = tokens[index]
        if index < tokens.count - 1 { index += 1 }
        return t
    }

    public mutating func matchKeyword(_ kw: String) -> Bool {
        if case .keyword(let k) = current.kind, k == kw { advance(); return true }
        return false
    }

    /// Consumes any run of the given keywords, in order, returning true if
    /// every keyword matched. On failure the cursor is left unchanged.
    public mutating func matchKeywords(_ kws: [String]) -> Bool {
        let saved = index
        for kw in kws {
            if case .keyword(let k) = tokens[index].kind, k == kw {
                if index < tokens.count - 1 { index += 1 }
            } else {
                index = saved
                return false
            }
        }
        return true
    }

    public mutating func matchPunctuation(_ byte: UInt8) -> Bool {
        if case .punctuation(let b) = current.kind, b == byte { advance(); return true }
        return false
    }

    public mutating func matchOperator(_ op: String) -> Bool {
        if case .operator(let s) = current.kind, s == op { advance(); return true }
        return false
    }

    public func isKeyword(_ kw: String) -> Bool {
        if case .keyword(let k) = current.kind, k == kw { return true }
        return false
    }

    public func isPunctuation(_ byte: UInt8) -> Bool {
        if case .punctuation(let b) = current.kind, b == byte { return true }
        return false
    }

    /// Read an identifier — bare or quoted. Advances the cursor. Returns nil
    /// on any other kind.
    public mutating func readIdentifier() -> Identifier? {
        switch current.kind {
        case .identifier:
            let t = advance()
            return Identifier(raw: t.text, quoted: false)
        case .quotedIdentifier:
            let t = advance()
            // Strip surrounding quote and unescape doubled quote.
            var raw = t.text
            if raw.count >= 2 {
                let first = raw.first!
                let last = raw.last!
                if first == last { raw = String(raw.dropFirst().dropLast()) }
                let doubled = "\(first)\(first)"
                raw = raw.replacingOccurrences(of: doubled, with: String(first))
            }
            return Identifier(raw: raw, quoted: true)
        case .keyword(let k):
            // Some contexts allow keywords as identifiers (e.g., column
            // names). Accept them but preserve the raw form.
            let t = advance()
            _ = k
            return Identifier(raw: t.text, quoted: false)
        default:
            return nil
        }
    }

    /// Read `schema.name` or just `name`.
    public mutating func readQualifiedIdentifier() -> Identifier? {
        guard var first = readIdentifier() else { return nil }
        if matchPunctuation(0x2E) { // '.'
            if let second = readIdentifier() {
                var qualified = second
                qualified.schema = first.raw
                return qualified
            }
        }
        _ = first
        return first
    }

    public mutating func skipTo(oneOf punctuation: [UInt8], keywords: [String] = [], respectParens: Bool = true) {
        var depth = 0
        while !isAtEnd {
            let tk = current
            switch tk.kind {
            case .punctuation(let b):
                if respectParens {
                    if b == 0x28 { depth += 1 }
                    else if b == 0x29 { depth = max(0, depth - 1); advance(); continue }
                }
                if depth == 0 && punctuation.contains(b) { return }
            case .keyword(let k):
                if depth == 0 && keywords.contains(k) { return }
            default:
                break
            }
            advance()
        }
    }

    public func range(from startToken: Token, to endToken: Token? = nil) -> SourceRange {
        let end = endToken ?? current
        let start = lineIndex.position(atByteOffset: startToken.byteOffset)
        let endPos = lineIndex.position(atByteOffset: end.byteOffset + end.byteLength)
        return SourceRange(
            file: file,
            startLine: start.line, startColumn: start.column,
            endLine: endPos.line, endColumn: endPos.column,
            byteOffset: startToken.byteOffset,
            byteLength: (end.byteOffset + end.byteLength) - startToken.byteOffset
        )
    }
}
