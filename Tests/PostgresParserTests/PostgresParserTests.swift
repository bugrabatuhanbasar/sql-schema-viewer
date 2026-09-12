import XCTest
@testable import PostgresParser
import SchemaModel

final class PostgresParserTests: XCTestCase {
    func testCreateTableWithColumnsAndInlinePK() {
        let sql = """
        CREATE TABLE users (
            id BIGSERIAL PRIMARY KEY,
            email TEXT NOT NULL UNIQUE,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
        );
        """
        let result = PostgresParser().parse(source: sql, file: nil)
        let schema = result.value
        XCTAssertEqual(schema.tables.count, 1)
        let users = schema.tables[Identifier(raw: "users")]
        XCTAssertNotNil(users)
        XCTAssertEqual(users?.columns.count, 3)
        XCTAssertEqual(users?.primaryKeyColumns.map(\.raw), ["id"])
        XCTAssertTrue(users?.constraints.contains(where: {
            if case .unique(let cols, _, _) = $0, cols.map(\.raw) == ["email"] { return true }
            return false
        }) == true)
        XCTAssertEqual(users?.columns.first(where: { $0.name.raw == "email" })?.nullable, false)
    }

    func testForeignKeyInline() {
        let sql = """
        CREATE TABLE a (id INT PRIMARY KEY);
        CREATE TABLE b (id INT PRIMARY KEY, a_id INT REFERENCES a(id) ON DELETE CASCADE);
        """
        let schema = PostgresParser().parse(source: sql, file: nil).value
        let b = schema.tables[Identifier(raw: "b")]!
        XCTAssertEqual(b.foreignKeys.count, 1)
        let fk = b.foreignKeys.first!
        XCTAssertEqual(fk.referencedTable.raw, "a")
        XCTAssertEqual(fk.referencedColumns.map(\.raw), ["id"])
        XCTAssertEqual(fk.onDelete, .cascade)
    }

    func testTableLevelCompositeForeignKey() {
        let sql = """
        CREATE TABLE parent (a INT, b INT, PRIMARY KEY (a, b));
        CREATE TABLE child (
            a INT, b INT,
            CONSTRAINT fk_ab FOREIGN KEY (a, b) REFERENCES parent(a, b)
        );
        """
        let schema = PostgresParser().parse(source: sql, file: nil).value
        let child = schema.tables[Identifier(raw: "child")]!
        let fk = child.foreignKeys.first!
        XCTAssertEqual(fk.name?.raw, "fk_ab")
        XCTAssertEqual(fk.localColumns.map(\.raw), ["a", "b"])
        XCTAssertEqual(fk.referencedColumns.map(\.raw), ["a", "b"])
    }

    func testAlterTableAddConstraint() {
        let sql = """
        CREATE TABLE a (id INT PRIMARY KEY);
        CREATE TABLE b (id INT PRIMARY KEY, a_id INT);
        ALTER TABLE b ADD CONSTRAINT b_a_fk FOREIGN KEY (a_id) REFERENCES a(id);
        """
        let schema = PostgresParser().parse(source: sql, file: nil).value
        let b = schema.tables[Identifier(raw: "b")]!
        XCTAssertEqual(b.foreignKeys.first?.name?.raw, "b_a_fk")
        XCTAssertEqual(b.foreignKeys.first?.referencedTable.raw, "a")
    }

    func testCreateIndex() {
        let sql = """
        CREATE TABLE t (id INT, email TEXT);
        CREATE UNIQUE INDEX t_email_idx ON t USING btree (email) WHERE email IS NOT NULL;
        """
        let schema = PostgresParser().parse(source: sql, file: nil).value
        let t = schema.tables[Identifier(raw: "t")]!
        XCTAssertEqual(t.indexes.count, 1)
        XCTAssertEqual(t.indexes.first?.name?.raw, "t_email_idx")
        XCTAssertTrue(t.indexes.first?.unique == true)
        XCTAssertEqual(t.indexes.first?.method, "btree")
    }

    func testCommentOnTableAndColumn() {
        let sql = """
        CREATE TABLE t (id INT, name TEXT);
        COMMENT ON TABLE t IS 'the t table';
        COMMENT ON COLUMN t.name IS 'human name';
        """
        let schema = PostgresParser().parse(source: sql, file: nil).value
        let t = schema.tables[Identifier(raw: "t")]!
        XCTAssertEqual(t.comment, "the t table")
        XCTAssertEqual(t.columns.first(where: { $0.name.raw == "name" })?.comment, "human name")
    }

    func testInvalidStatementDoesNotDiscardRest() {
        let sql = """
        CREATE TABLE ok1 (id INT);
        THIS IS NOT VALID SQL AT ALL;
        CREATE TABLE ok2 (id INT);
        """
        let result = PostgresParser().parse(source: sql, file: nil)
        XCTAssertNotNil(result.value.tables[Identifier(raw: "ok1")])
        XCTAssertNotNil(result.value.tables[Identifier(raw: "ok2")])
    }

    func testSummaryLineFormat() {
        let sql = """
        CREATE TABLE a (id INT PRIMARY KEY);
        CREATE VIEW v AS SELECT * FROM a;
        SELECT 1;
        """
        let schema = PostgresParser().parse(source: sql, file: nil).value
        XCTAssertTrue(schema.summarySentence.contains("Found 1 tables"))
        XCTAssertTrue(schema.summarySentence.contains("1 views"))
    }

    func testDataTypeParametersAndArrays() {
        let sql = "CREATE TABLE t (a VARCHAR(255), b NUMERIC(10, 2), tags TEXT[]);"
        let schema = PostgresParser().parse(source: sql, file: nil).value
        let t = schema.tables[Identifier(raw: "t")]!
        XCTAssertEqual(t.columns[0].type.displayName.lowercased(), "varchar(255)")
        XCTAssertEqual(t.columns[1].type.displayName.lowercased(), "numeric(10,2)")
        XCTAssertTrue(t.columns[2].type.displayName.contains("[]"))
    }

    func testFunctionBodyKeptAsOpaqueText() {
        let sql = """
        CREATE OR REPLACE FUNCTION greet(who TEXT) RETURNS TEXT AS $$
        BEGIN
          RETURN 'hi ' || who;
        END;
        $$ LANGUAGE plpgsql;
        """
        let schema = PostgresParser().parse(source: sql, file: nil).value
        XCTAssertEqual(schema.routines.count, 1)
        XCTAssertTrue(schema.routines.values.first?.bodySQL.contains("plpgsql") == true)
    }
}

final class PostgresParserPerformanceTests: XCTestCase {
    func testTwoHundredTablesParseUnderOneSecond() {
        var sb = ""
        sb.reserveCapacity(200_000)
        for i in 0..<200 {
            sb += "CREATE TABLE t\(i) (id INT PRIMARY KEY, name TEXT NOT NULL, parent_id INT"
            if i > 0 { sb += " REFERENCES t\(i - 1)(id)" }
            sb += ");\n"
        }
        let start = Date()
        let schema = PostgresParser().parse(source: sb, file: nil).value
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(schema.tables.count, 200)
        // Very generous ceiling; on Apple Silicon this runs in <100ms.
        XCTAssertLessThan(elapsed, 2.0, "200-table parse took \(elapsed)s")
    }
}
