import XCTest
@testable import DBMLParser
import SchemaModel

final class DBMLParserTests: XCTestCase {
    func testTableWithInlinePkAndColumnRef() {
        let dbml = """
        Table users {
          id integer [pk, increment]
          email varchar [unique, not null]
        }

        Table posts {
          id integer [pk]
          user_id integer [ref: > users.id]
          title varchar
        }
        """
        let schema = DBMLParser().parse(source: dbml, file: nil).value
        XCTAssertEqual(schema.tables.count, 2)
        let posts = schema.tables[Identifier(raw: "posts")]!
        XCTAssertEqual(posts.foreignKeys.first?.referencedTable.raw, "users")
        XCTAssertEqual(posts.foreignKeys.first?.localColumns.map(\.raw), ["user_id"])
        let users = schema.tables[Identifier(raw: "users")]!
        XCTAssertEqual(users.primaryKeyColumns.map(\.raw), ["id"])
        XCTAssertTrue(users.constraints.contains(where: {
            if case .unique(let cols, _, _) = $0, cols.map(\.raw) == ["email"] { return true }
            return false
        }))
    }

    func testTopLevelRefAttachesToOwner() {
        let dbml = """
        Table a { id integer [pk] }
        Table b { id integer [pk], a_id integer }
        Ref: b.a_id > a.id
        """
        let schema = DBMLParser().parse(source: dbml, file: nil).value
        let b = schema.tables[Identifier(raw: "b")]!
        XCTAssertEqual(b.foreignKeys.first?.referencedTable.raw, "a")
    }

    func testExportRoundTripsCorePieces() {
        var schema = Schema(dialect: .postgres)
        let users = Identifier(raw: "users")
        let posts = Identifier(raw: "posts")
        schema.tables[users] = Table(
            name: users,
            columns: [
                Column(name: Identifier(raw: "id"), type: .named("bigserial", params: []), nullable: false),
                Column(name: Identifier(raw: "email"), type: .named("text", params: []), nullable: false),
            ],
            constraints: [
                .primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero),
                .notNull(column: Identifier(raw: "id"), source: .zero),
                .notNull(column: Identifier(raw: "email"), source: .zero),
            ]
        )
        schema.tables[posts] = Table(
            name: posts,
            columns: [
                Column(name: Identifier(raw: "id"), type: .named("bigserial", params: []), nullable: false),
                Column(name: Identifier(raw: "user_id"), type: .named("bigint", params: []), nullable: false),
            ],
            constraints: [
                .primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero),
                .foreignKey(ForeignKeySpec(
                    localColumns: [Identifier(raw: "user_id")],
                    referencedTable: users,
                    referencedColumns: [Identifier(raw: "id")]
                )),
            ]
        )
        let text = DBMLExporter.export(schema).value
        XCTAssertTrue(text.contains("Table users"))
        XCTAssertTrue(text.contains("Table posts"))
        XCTAssertTrue(text.contains("Ref: posts.user_id > users.id"))
    }

    func testUnknownBlockDoesNotBreakParse() {
        let dbml = """
        Enum role { admin, member }
        Table users { id integer [pk] }
        """
        let schema = DBMLParser().parse(source: dbml, file: nil).value
        XCTAssertNotNil(schema.tables[Identifier(raw: "users")])
    }
}
