import XCTest
@testable import OracleParser
import SchemaModel

final class OracleParserTests: XCTestCase {
    func testCreateTableWithOracleTypes() {
        let sql = """
        CREATE TABLE customers (
            id NUMBER(10) PRIMARY KEY,
            name VARCHAR2(255) NOT NULL,
            joined DATE DEFAULT SYSDATE,
            balance NUMBER(15, 2)
        );
        """
        let schema = OracleParser().parse(source: sql, file: nil).value
        let t = schema.tables[Identifier(raw: "customers")]!
        XCTAssertEqual(t.columns.count, 4)
        XCTAssertEqual(t.primaryKeyColumns.map(\.raw), ["id"])
        XCTAssertTrue(t.columns.contains { $0.name.raw == "name" && !$0.nullable })
    }

    func testForeignKeyAndComment() {
        let sql = """
        CREATE TABLE parent (id NUMBER PRIMARY KEY);
        CREATE TABLE child (
            id NUMBER PRIMARY KEY,
            parent_id NUMBER,
            CONSTRAINT fk FOREIGN KEY (parent_id) REFERENCES parent(id) ON DELETE CASCADE
        );
        COMMENT ON TABLE child IS 'child rows';
        COMMENT ON COLUMN child.parent_id IS 'fk column';
        """
        let schema = OracleParser().parse(source: sql, file: nil).value
        let c = schema.tables[Identifier(raw: "child")]!
        XCTAssertEqual(c.foreignKeys.first?.referencedTable.raw, "parent")
        XCTAssertEqual(c.foreignKeys.first?.onDelete, .cascade)
        XCTAssertEqual(c.comment, "child rows")
        XCTAssertEqual(c.columns.first(where: { $0.name.raw == "parent_id" })?.comment, "fk column")
    }

    func testAlterTableAddConstraint() {
        let sql = """
        CREATE TABLE a (id NUMBER PRIMARY KEY);
        CREATE TABLE b (id NUMBER PRIMARY KEY, a_id NUMBER);
        ALTER TABLE b ADD CONSTRAINT fk_b_a FOREIGN KEY (a_id) REFERENCES a(id);
        """
        let schema = OracleParser().parse(source: sql, file: nil).value
        let b = schema.tables[Identifier(raw: "b")]!
        XCTAssertEqual(b.foreignKeys.first?.name?.raw, "fk_b_a")
    }

    func testTimestampWithTimeZone() {
        let sql = "CREATE TABLE t (ts TIMESTAMP WITH LOCAL TIME ZONE);"
        let schema = OracleParser().parse(source: sql, file: nil).value
        let t = schema.tables[Identifier(raw: "t")]!
        XCTAssertTrue(t.columns.first!.type.displayName.uppercased().contains("TIMESTAMP"))
    }

    func testCreateSequenceIsIgnoredNotFailed() {
        let sql = "CREATE SEQUENCE s START WITH 1 INCREMENT BY 1 NOCACHE; CREATE TABLE t (id NUMBER PRIMARY KEY);"
        let schema = OracleParser().parse(source: sql, file: nil).value
        XCTAssertNotNil(schema.tables[Identifier(raw: "t")])
    }

    func testPackageBodyKeptAsPartialRoutine() {
        let sql = """
        CREATE OR REPLACE PROCEDURE hello(who IN VARCHAR2) IS
        BEGIN
          DBMS_OUTPUT.PUT_LINE('hi ' || who);
        END;
        """
        let schema = OracleParser().parse(source: sql, file: nil).value
        XCTAssertEqual(schema.routines.count, 1)
        XCTAssertEqual(schema.routines.values.first?.kind, .procedure)
    }
}
