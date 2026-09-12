import XCTest
@testable import DialectDetector
import SchemaModel

final class DialectDetectorTests: XCTestCase {
    func testDbmlFilename() {
        XCTAssertEqual(DialectDetector.detect(fromContents: "Table users { id int }", filename: "schema.dbml"), .dbml)
    }
    func testPostgresSerialAndDollarQuotes() {
        XCTAssertEqual(DialectDetector.detect(fromContents: "CREATE TABLE t (id SERIAL PRIMARY KEY);"), .postgres)
        XCTAssertEqual(DialectDetector.detect(fromContents: "CREATE FUNCTION f() RETURNS void AS $$ BEGIN RETURN; END; $$"), .postgres)
    }
    func testMySQLBackticks() {
        XCTAssertEqual(DialectDetector.detect(fromContents: "CREATE TABLE `t` (id INT AUTO_INCREMENT) ENGINE=InnoDB;"), .mysql)
    }
    func testSQLiteAutoincrement() {
        XCTAssertEqual(DialectDetector.detect(fromContents: "CREATE TABLE t (id INTEGER PRIMARY KEY AUTOINCREMENT) WITHOUT ROWID;"), .sqlite)
    }
    func testOracleVarchar2() {
        XCTAssertEqual(DialectDetector.detect(fromContents: "CREATE TABLE t (id NUMBER(10), name VARCHAR2(255));"), .oracle)
    }
    func testUnknownFallback() {
        XCTAssertEqual(DialectDetector.detect(fromContents: "-- just a comment\n"), .unknown)
    }
}
