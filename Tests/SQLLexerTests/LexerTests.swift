import XCTest
@testable import SQLLexer
import SchemaModel

final class LexerTests: XCTestCase {
    func testKeywordAndIdentifier() {
        let buf = SourceBuffer("CREATE TABLE users (id INT);")
        let lx = Lexer(buf, config: .postgres)
        let tokens = lx.tokenize()
        XCTAssertEqual(tokens.first?.kind, .keyword("CREATE"))
        XCTAssertTrue(tokens.contains(where: {
            if case .identifier = $0.kind, $0.text == "users" { return true }
            return false
        }))
    }

    func testStringLiteralWithEscape() {
        let buf = SourceBuffer("'it''s ok'")
        let lx = Lexer(buf, config: .postgres)
        let tokens = lx.tokenize()
        XCTAssertEqual(tokens.first?.kind, .stringLiteral)
        XCTAssertEqual(tokens.first?.text, "'it''s ok'")
    }

    func testPostgresDollarQuoting() {
        let src = "$$hello ; world$$"
        let buf = SourceBuffer(src)
        let lx = Lexer(buf, config: .postgres)
        let tokens = lx.tokenize()
        XCTAssertEqual(tokens.first?.kind, .dollarQuotedString)
    }

    func testMySQLBackticksIdentifier() {
        let buf = SourceBuffer("SELECT `id` FROM `t`")
        let lx = Lexer(buf, config: .mysql)
        let tokens = lx.tokenize()
        XCTAssertTrue(tokens.contains(where: {
            if case .quotedIdentifier = $0.kind, $0.text == "`id`" { return true }
            return false
        }))
    }

    func testLineAndBlockComments() {
        let buf = SourceBuffer("-- hi\n/* nested /* inner */ done */ id")
        let lx = Lexer(buf, config: .postgres)
        let tokens = lx.tokenize()
        XCTAssertTrue(tokens.contains { if case .identifier = $0.kind, $0.text == "id" { return true } else { return false } })
    }

    func testSourceRangeLineColumn() {
        let src = "line1\nCREATE"
        let buf = SourceBuffer(src)
        let index = LineIndex(buf)
        let tokens = Lexer(buf, config: .postgres).tokenize()
        guard let create = tokens.first(where: { if case .keyword("CREATE") = $0.kind { return true } else { return false } }) else {
            XCTFail("missing CREATE"); return
        }
        let range = create.sourceRange(file: nil, using: index)
        XCTAssertEqual(range.startLine, 2)
        XCTAssertEqual(range.startColumn, 1)
    }
}
