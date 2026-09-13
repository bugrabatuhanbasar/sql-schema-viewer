import Foundation
import SchemaModel
import SQLLexer

/// Scans an opaque SQL body (view definition, trigger/function/procedure
/// body) for referenced tables. Uses the shared SQL lexer with the
/// PostgreSQL config as a reasonable default — the surface features we
/// need (FROM, JOIN, INSERT INTO, UPDATE, DELETE FROM, EXECUTE IMMEDIATE)
/// are dialect-neutral.
///
/// Any reference whose target is dynamic (built from a string via `||`,
/// concatenation inside `EXECUTE IMMEDIATE`, or otherwise not a bare
/// identifier) is emitted with `.partial` confidence, as the spec
/// requires.
public struct BodyScanner: Sendable {
    public struct Result: Sendable {
        public var reads: [Reference]
        public var writes: [Reference]
        public init(reads: [Reference] = [], writes: [Reference] = []) {
            self.reads = reads; self.writes = writes
        }
    }

    public init() {}

    public func scan(body: String) -> Result {
        let buffer = SourceBuffer(body)
        let tokens = Lexer(buffer, config: LexerConfig(
            dialect: .postgres,
            identifierQuote: 0x22,
            alternateIdentifierQuote: 0x60,
            supportsDollarQuoting: true,
            supportsHashComments: true,
            keywords: BodyScanner.keywords
        )).tokenize().filter {
            switch $0.kind {
            case .whitespace, .lineComment, .blockComment: return false
            default: return true
            }
        }

        var reads: [Reference] = []
        var writes: [Reference] = []
        var dynamicMode = false
        var i = 0

        func readIdent(from idx: Int) -> (Identifier, Int)? {
            var k = idx
            guard k < tokens.count else { return nil }
            let first: String
            switch tokens[k].kind {
            case .identifier: first = tokens[k].text
            case .quotedIdentifier:
                var raw = tokens[k].text
                if raw.count >= 2 { raw = String(raw.dropFirst().dropLast()) }
                first = raw
            case .keyword(let kw):
                // Some places allow keyword-as-identifier; treat cautiously.
                first = kw
            default:
                return nil
            }
            k += 1
            // Optional schema qualification: `schema.table` — collapse the
            // schema and treat the tail as the base name.
            if k < tokens.count, case .punctuation(0x2E) = tokens[k].kind {
                k += 1
                if k < tokens.count {
                    switch tokens[k].kind {
                    case .identifier:
                        return (Identifier(raw: tokens[k].text, schema: first), k + 1)
                    case .quotedIdentifier:
                        var raw = tokens[k].text
                        if raw.count >= 2 { raw = String(raw.dropFirst().dropLast()) }
                        return (Identifier(raw: raw, quoted: true, schema: first), k + 1)
                    default: break
                    }
                }
            }
            return (Identifier(raw: first), k)
        }

        while i < tokens.count {
            let t = tokens[i]
            switch t.kind {
            case .keyword(let kw):
                switch kw {
                case "EXECUTE":
                    // EXECUTE IMMEDIATE 'string' — pull references out of
                    // the string literal and mark them partial. Everything
                    // that follows in this statement remains dynamic.
                    dynamicMode = true
                    if i + 1 < tokens.count, case .keyword("IMMEDIATE") = tokens[i + 1].kind,
                       i + 2 < tokens.count, case .stringLiteral = tokens[i + 2].kind {
                        var body = tokens[i + 2].text
                        if body.hasPrefix("'") && body.hasSuffix("'") {
                            body = String(body.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
                        }
                        let inner = scan(body: body)
                        for r in inner.reads {
                            reads.append(Reference(target: r.target, kind: r.kind, confidence: .partial))
                        }
                        for r in inner.writes {
                            writes.append(Reference(target: r.target, kind: r.kind, confidence: .partial))
                        }
                        i += 3
                        continue
                    }
                case "FROM", "JOIN":
                    if i + 1 < tokens.count, let (id, next) = readIdent(from: i + 1) {
                        let conf: ParseConfidence = dynamicMode ? .partial : .complete
                        reads.append(Reference(target: id, kind: .table, confidence: conf))
                        i = next
                        continue
                    }
                case "INTO":
                    // INSERT INTO / SELECT INTO
                    if i + 1 < tokens.count, let (id, next) = readIdent(from: i + 1) {
                        let conf: ParseConfidence = dynamicMode ? .partial : .complete
                        writes.append(Reference(target: id, kind: .table, confidence: conf))
                        i = next
                        continue
                    }
                case "UPDATE":
                    if i + 1 < tokens.count, let (id, next) = readIdent(from: i + 1) {
                        let conf: ParseConfidence = dynamicMode ? .partial : .complete
                        writes.append(Reference(target: id, kind: .table, confidence: conf))
                        i = next
                        continue
                    }
                case "DELETE":
                    // DELETE FROM table
                    if i + 2 < tokens.count,
                       case .keyword("FROM") = tokens[i + 1].kind,
                       let (id, next) = readIdent(from: i + 2) {
                        let conf: ParseConfidence = dynamicMode ? .partial : .complete
                        writes.append(Reference(target: id, kind: .table, confidence: conf))
                        i = next
                        continue
                    }
                default:
                    break
                }
            case .punctuation(0x3B):
                dynamicMode = false // reset at statement boundary
            default: break
            }
            i += 1
        }
        return Result(reads: dedupe(reads), writes: dedupe(writes))
    }

    private func dedupe(_ refs: [Reference]) -> [Reference] {
        var seen = Set<Identifier>()
        var out: [Reference] = []
        for r in refs where !seen.contains(r.target) {
            seen.insert(r.target); out.append(r)
        }
        return out
    }

    private static let keywords: Set<String> = LexerConfig.commonKeywords.union([
        "FROM", "JOIN", "INTO", "EXECUTE", "IMMEDIATE",
    ])
}
