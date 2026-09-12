import XCTest
@testable import ParserCore
import SQLLexer
import SchemaModel

final class StatementSplitterTests: XCTestCase {
    func testSplitsOnTopLevelSemicolons() {
        let src = "CREATE TABLE a(id int); CREATE TABLE b(id int);"
        let splitter = StatementSplitter(config: .postgres)
        let slices = splitter.split(SourceBuffer(src))
        XCTAssertEqual(slices.count, 2)
    }

    func testDoesNotSplitInsideParens() {
        let src = "CREATE TABLE t(id int, name text CHECK (name <> ';'));"
        let splitter = StatementSplitter(config: .postgres)
        let slices = splitter.split(SourceBuffer(src))
        XCTAssertEqual(slices.count, 1)
    }

    func testDoesNotSplitInsideDollarQuotes() {
        let src = "CREATE FUNCTION f() RETURNS void AS $$ BEGIN SELECT 1; END; $$ LANGUAGE plpgsql;"
        let splitter = StatementSplitter(config: .postgres)
        let slices = splitter.split(SourceBuffer(src))
        XCTAssertEqual(slices.count, 1)
    }

    func testTrailingStatementWithoutSemicolonIsCaptured() {
        let src = "CREATE TABLE a(id int); CREATE TABLE b(id int)"
        let splitter = StatementSplitter(config: .postgres)
        let slices = splitter.split(SourceBuffer(src))
        XCTAssertEqual(slices.count, 2)
    }

    func testCommentsAloneDoNotProduceSlice() {
        let src = "-- just a comment\n/* another */\n"
        let splitter = StatementSplitter(config: .postgres)
        let slices = splitter.split(SourceBuffer(src))
        XCTAssertEqual(slices.count, 0)
    }
}
