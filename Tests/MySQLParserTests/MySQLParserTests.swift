import XCTest
@testable import MySQLParser
import SchemaModel

final class MySQLParserTests: XCTestCase {
    func testBackticksAndAutoIncrement() {
        let sql = """
        CREATE TABLE `users` (
            `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            `email` VARCHAR(255) NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `users_email_uq` (`email`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """
        let schema = MySQLParser(flavor: .mysql).parse(source: sql, file: nil).value
        // Backticks preserve case; equality uses normalized form for unquoted only.
        let key = Identifier(raw: "users", quoted: true)
        let users = schema.tables[key]
        XCTAssertNotNil(users)
        XCTAssertEqual(users?.primaryKeyColumns.map(\.raw), ["id"])
        XCTAssertTrue(users?.constraints.contains(where: {
            if case .unique(let cols, _, _) = $0, cols.map(\.raw) == ["email"] { return true }
            return false
        }) == true)
        XCTAssertEqual(users?.columns.count, 2)
    }

    func testForeignKey() {
        let sql = """
        CREATE TABLE `a` (`id` INT PRIMARY KEY);
        CREATE TABLE `b` (
            `id` INT PRIMARY KEY,
            `a_id` INT,
            CONSTRAINT `fk_b_a` FOREIGN KEY (`a_id`) REFERENCES `a`(`id`) ON DELETE CASCADE
        );
        """
        let schema = MySQLParser(flavor: .mysql).parse(source: sql, file: nil).value
        let b = schema.tables[Identifier(raw: "b", quoted: true)]
        XCTAssertEqual(b?.foreignKeys.count, 1)
        XCTAssertEqual(b?.foreignKeys.first?.referencedTable.raw, "a")
        XCTAssertEqual(b?.foreignKeys.first?.onDelete, .cascade)
    }

    func testAlterTableAddConstraint() {
        let sql = """
        CREATE TABLE a (id INT PRIMARY KEY);
        CREATE TABLE b (id INT PRIMARY KEY, a_id INT);
        ALTER TABLE b ADD CONSTRAINT fk FOREIGN KEY (a_id) REFERENCES a(id);
        """
        let schema = MySQLParser(flavor: .mysql).parse(source: sql, file: nil).value
        let b = schema.tables[Identifier(raw: "b")]
        XCTAssertEqual(b?.foreignKeys.first?.referencedTable.raw, "a")
    }

    func testFaultToleranceKeepsRestOfFile() {
        let sql = """
        CREATE TABLE ok1 (id INT);
        THIS IS NOT VALID AT ALL;
        CREATE TABLE ok2 (id INT);
        garbage garbage garbage;
        CREATE TABLE ok3 (id INT);
        """
        let schema = MySQLParser(flavor: .mysql).parse(source: sql, file: nil).value
        XCTAssertNotNil(schema.tables[Identifier(raw: "ok1")])
        XCTAssertNotNil(schema.tables[Identifier(raw: "ok2")])
        XCTAssertNotNil(schema.tables[Identifier(raw: "ok3")])
    }

    func testMariaDBFlavorTagsDialect() {
        let sql = "CREATE TABLE t (id INT PRIMARY KEY);"
        let schema = MySQLParser(flavor: .mariadb).parse(source: sql, file: nil).value
        XCTAssertEqual(schema.dialect, .mariadb)
    }

    func testEngineTrailerIgnored() {
        let sql = "CREATE TABLE t (id INT PRIMARY KEY) ENGINE=InnoDB ROW_FORMAT=DYNAMIC;"
        let schema = MySQLParser(flavor: .mysql).parse(source: sql, file: nil).value
        XCTAssertNotNil(schema.tables[Identifier(raw: "t")])
    }

    func testSummaryWordingMatchesSpecExample() {
        // 5 tables all valid, no views/functions, no skipped -> matches
        // "Fully parsed 5 objects, partially parsed 0 objects, and skipped 0 unsupported statements."
        var sql = ""
        for i in 0..<5 { sql += "CREATE TABLE t\(i) (id INT PRIMARY KEY);\n" }
        let schema = MySQLParser(flavor: .mysql).parse(source: sql, file: nil).value
        XCTAssertTrue(schema.summarySentence.contains("Fully parsed 5 objects"))
        XCTAssertTrue(schema.summarySentence.contains("skipped 0 unsupported statements"))
    }
}
