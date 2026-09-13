import XCTest
@testable import QualityChecks
import SchemaModel

final class QualityChecksTests: XCTestCase {
    func testMissingPrimaryKey() {
        var s = Schema()
        s.tables[Identifier(raw: "t")] = Table(name: Identifier(raw: "t"), columns: [
            Column(name: Identifier(raw: "id"), type: .named("int", params: []))
        ])
        let out = QualityChecks.run(on: s)
        XCTAssertTrue(out.contains { $0.code == "W0010" })
    }

    func testIncompatibleFKTypes() {
        var s = Schema()
        let a = Identifier(raw: "a"), b = Identifier(raw: "b")
        s.tables[a] = Table(name: a, columns: [
            Column(name: Identifier(raw: "id"), type: .named("text", params: []))
        ], constraints: [.primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero)])
        s.tables[b] = Table(name: b, columns: [
            Column(name: Identifier(raw: "id"), type: .named("int", params: []), nullable: false),
            Column(name: Identifier(raw: "a_id"), type: .named("int", params: []))
        ], constraints: [
            .primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero),
            .foreignKey(ForeignKeySpec(
                localColumns: [Identifier(raw: "a_id")],
                referencedTable: a,
                referencedColumns: [Identifier(raw: "id")]
            ))
        ])
        let out = QualityChecks.run(on: s)
        XCTAssertTrue(out.contains { $0.code == "W0011" })
    }

    func testUnindexedFKColumn() {
        var s = Schema()
        let a = Identifier(raw: "a")
        s.tables[a] = Table(name: a, columns: [
            Column(name: Identifier(raw: "id"), type: .named("int", params: []))
        ], constraints: [.primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero)])
        s.tables[Identifier(raw: "b")] = Table(
            name: Identifier(raw: "b"),
            columns: [
                Column(name: Identifier(raw: "id"), type: .named("int", params: [])),
                Column(name: Identifier(raw: "a_id"), type: .named("int", params: [])),
            ],
            constraints: [
                .primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero),
                .foreignKey(ForeignKeySpec(
                    localColumns: [Identifier(raw: "a_id")],
                    referencedTable: a,
                    referencedColumns: [Identifier(raw: "id")]
                ))
            ]
        )
        let out = QualityChecks.run(on: s)
        XCTAssertTrue(out.contains { $0.code == "W0012" })
    }

    func testSuspectedFKColumn() {
        var s = Schema()
        s.tables[Identifier(raw: "t")] = Table(name: Identifier(raw: "t"), columns: [
            Column(name: Identifier(raw: "id"), type: .named("int", params: [])),
            Column(name: Identifier(raw: "other_id"), type: .named("int", params: []))
        ], constraints: [.primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero)])
        let out = QualityChecks.run(on: s)
        XCTAssertTrue(out.contains { $0.code == "W0013" })
    }

    func testDuplicateColumn() {
        var s = Schema()
        s.tables[Identifier(raw: "t")] = Table(name: Identifier(raw: "t"), columns: [
            Column(name: Identifier(raw: "id"), type: .named("int", params: [])),
            Column(name: Identifier(raw: "id"), type: .named("int", params: [])),
        ], constraints: [.primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero)])
        let out = QualityChecks.run(on: s)
        XCTAssertTrue(out.contains { $0.code == "W0014" })
    }

    func testOrphanTable() {
        var s = Schema()
        s.tables[Identifier(raw: "island")] = Table(name: Identifier(raw: "island"), columns: [
            Column(name: Identifier(raw: "id"), type: .named("int", params: []))
        ], constraints: [.primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero)])
        let out = QualityChecks.run(on: s)
        XCTAssertTrue(out.contains { $0.code == "W0015" })
    }

    func testCircularDependency() {
        var s = Schema()
        let a = Identifier(raw: "a"), b = Identifier(raw: "b")
        s.tables[a] = Table(name: a, columns: [Column(name: Identifier(raw: "id"), type: .named("int", params: []))],
                            constraints: [
                                .primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero),
                                .foreignKey(ForeignKeySpec(localColumns: [Identifier(raw: "b_id")], referencedTable: b, referencedColumns: [Identifier(raw: "id")]))
                            ])
        s.tables[b] = Table(name: b, columns: [Column(name: Identifier(raw: "id"), type: .named("int", params: []))],
                            constraints: [
                                .primaryKey(columns: [Identifier(raw: "id")], name: nil, source: .zero),
                                .foreignKey(ForeignKeySpec(localColumns: [Identifier(raw: "a_id")], referencedTable: a, referencedColumns: [Identifier(raw: "id")]))
                            ])
        let out = QualityChecks.run(on: s)
        XCTAssertTrue(out.contains { $0.code == "W0017" })
    }

    func testDanglingReference() {
        var s = Schema()
        s.tables[Identifier(raw: "b")] = Table(name: Identifier(raw: "b"),
            columns: [Column(name: Identifier(raw: "a_id"), type: .named("int", params: []))],
            constraints: [.foreignKey(ForeignKeySpec(
                localColumns: [Identifier(raw: "a_id")],
                referencedTable: Identifier(raw: "ghost"),
                referencedColumns: [Identifier(raw: "id")]
            ))]
        )
        let out = QualityChecks.run(on: s)
        XCTAssertTrue(out.contains { $0.code == "W0016" })
    }
}
