import XCTest
@testable import SQLiteParser
import SchemaModel

final class SQLiteParserTests: XCTestCase {
    func testIntegerPrimaryKeyAutoincrement() {
        let sql = """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        ) WITHOUT ROWID;
        """
        let schema = SQLiteParser().parse(source: sql, file: nil).value
        let t = schema.tables[Identifier(raw: "users")]
        XCTAssertNotNil(t)
        XCTAssertEqual(t?.primaryKeyColumns.map(\.raw), ["id"])
        XCTAssertEqual(t?.columns.count, 3)
    }

    func testFKComposite() {
        let sql = """
        CREATE TABLE parent (a INT, b INT, PRIMARY KEY (a, b));
        CREATE TABLE child (
            a INT, b INT,
            FOREIGN KEY (a, b) REFERENCES parent(a, b) ON DELETE CASCADE
        );
        """
        let schema = SQLiteParser().parse(source: sql, file: nil).value
        let child = schema.tables[Identifier(raw: "child")]!
        XCTAssertEqual(child.foreignKeys.first?.referencedTable.raw, "parent")
        XCTAssertEqual(child.foreignKeys.first?.localColumns.map(\.raw), ["a", "b"])
        XCTAssertEqual(child.foreignKeys.first?.onDelete, .cascade)
    }

    func testPragmaIsIgnored() {
        let sql = "PRAGMA foreign_keys = ON; CREATE TABLE t (id INT PRIMARY KEY);"
        let schema = SQLiteParser().parse(source: sql, file: nil).value
        XCTAssertNotNil(schema.tables[Identifier(raw: "t")])
    }

    func testCreateIndexAttachesToTable() {
        let sql = """
        CREATE TABLE t (id INT, email TEXT);
        CREATE UNIQUE INDEX t_email_idx ON t (email);
        """
        let schema = SQLiteParser().parse(source: sql, file: nil).value
        let t = schema.tables[Identifier(raw: "t")]!
        XCTAssertEqual(t.indexes.first?.name?.raw, "t_email_idx")
        XCTAssertTrue(t.indexes.first?.unique == true)
    }
}
