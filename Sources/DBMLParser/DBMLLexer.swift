import Foundation
import SchemaModel

/// Tiny character-oriented DBML scanner. Not a full lexer — just enough
/// helpers for the parser to consume words, punctuation, strings, and
/// bracketed setting lists.
struct DBMLLexer {
    let source: [Character]
    var index: Int = 0
    var line: Int = 1
    var column: Int = 1

    struct Location { var line: Int; var column: Int }

    init(source: String) {
        self.source = Array(source)
    }

    var isAtEnd: Bool { index >= source.count }
    var location: Location { Location(line: line, column: column) }

    mutating func advance() {
        guard !isAtEnd else { return }
        let ch = source[index]
        if ch == "\n" { line += 1; column = 1 } else { column += 1 }
        index += 1
    }

    func peek(offset: Int = 0) -> Character? {
        let j = index + offset
        return j < source.count ? source[j] : nil
    }

    mutating func skipTrivia() {
        while !isAtEnd {
            let ch = source[index]
            if ch.isWhitespace { advance(); continue }
            if ch == "/", peek(offset: 1) == "/" {
                while !isAtEnd, source[index] != "\n" { advance() }
                continue
            }
            if ch == "/", peek(offset: 1) == "*" {
                advance(); advance()
                while !isAtEnd {
                    if source[index] == "*", peek(offset: 1) == "/" { advance(); advance(); break }
                    advance()
                }
                continue
            }
            break
        }
    }

    mutating func consume(_ literal: String) -> Bool {
        let chars = Array(literal)
        guard index + chars.count <= source.count else { return false }
        for (i, c) in chars.enumerated() where source[index + i] != c { return false }
        for _ in 0..<chars.count { advance() }
        return true
    }

    func check(_ literal: String) -> Bool {
        let chars = Array(literal)
        guard index + chars.count <= source.count else { return false }
        for (i, c) in chars.enumerated() where source[index + i] != c { return false }
        return true
    }

    /// Read an unquoted or double-quoted word. A word begins with a letter
    /// or underscore and continues with letters/digits/underscore.
    mutating func readWord() -> String? {
        skipTrivia()
        guard !isAtEnd else { return nil }
        if source[index] == "\"" {
            advance()
            var out = ""
            while !isAtEnd, source[index] != "\"" { out.append(source[index]); advance() }
            if !isAtEnd { advance() }
            return out
        }
        let ch = source[index]
        guard ch.isLetter || ch == "_" else { return nil }
        var out = ""
        while !isAtEnd {
            let c = source[index]
            if c.isLetter || c.isNumber || c == "_" { out.append(c); advance() } else { break }
        }
        return out.isEmpty ? nil : out
    }

    func peekWord() -> String? {
        var scanner = self
        return scanner.readWord()
    }

    /// Read `schema.word` or bare `word`; returns (schema-or-table, name).
    mutating func readQualifiedWord() -> (Identifier, Identifier)? {
        guard let first = readWord() else { return nil }
        if consume(".") {
            guard let second = readWord() else { return nil }
            return (Identifier(raw: first), Identifier(raw: second))
        }
        return (Identifier(raw: first), Identifier(raw: first))
    }

    /// Read an atomic literal: number, string, or word.
    mutating func readAtom() -> String {
        skipTrivia()
        if isAtEnd { return "" }
        if source[index] == "'" || source[index] == "\"" || source[index] == "`" {
            return readString() ?? ""
        }
        var out = ""
        while !isAtEnd {
            let c = source[index]
            if c == "," || c == ")" || c == "]" || c.isWhitespace { break }
            out.append(c); advance()
        }
        return out
    }

    mutating func readString() -> String? {
        skipTrivia()
        guard !isAtEnd else { return nil }
        let quote = source[index]
        guard quote == "'" || quote == "\"" || quote == "`" else { return nil }
        advance()
        var out = ""
        while !isAtEnd {
            let c = source[index]
            if c == "\\", let n = peek(offset: 1) {
                out.append(n); advance(); advance(); continue
            }
            if c == quote { advance(); return out }
            out.append(c); advance()
        }
        return out
    }

    /// Skip a `[…]` settings list without interpreting it.
    mutating func skipBracketedSettings() -> Bool {
        skipTrivia()
        guard consume("[") else { return false }
        var depth = 1
        while !isAtEnd && depth > 0 {
            if consume("[") { depth += 1 }
            else if consume("]") { depth -= 1 }
            else { advance() }
        }
        return true
    }
}
