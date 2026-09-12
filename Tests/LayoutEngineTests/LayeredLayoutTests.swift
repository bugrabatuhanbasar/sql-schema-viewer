import XCTest
@testable import LayoutEngine
import SchemaModel

final class LayeredLayoutTests: XCTestCase {
    func testDeterministicPositions() {
        var schema = Schema()
        for name in ["b", "a", "c"] {
            schema.tables[Identifier(raw: name)] = Table(name: Identifier(raw: name))
        }
        let a = LayoutEngine.layout(schema)
        let b = LayoutEngine.layout(schema)
        XCTAssertEqual(a.positions.count, b.positions.count)
        for (p, q) in zip(a.positions, b.positions) {
            XCTAssertEqual(p.node.normalized, q.node.normalized)
            XCTAssertEqual(p.x, q.x)
            XCTAssertEqual(p.y, q.y)
        }
    }

    func testLayeredOrdersDependenciesTopDown() {
        // parent -> child edge; parent should be at a lower depth (y-coordinate).
        var schema = Schema()
        let p = Identifier(raw: "parent")
        let c = Identifier(raw: "child")
        schema.tables[p] = Table(name: p)
        schema.tables[c] = Table(name: c, constraints: [
            .foreignKey(ForeignKeySpec(
                localColumns: [Identifier(raw: "pid")],
                referencedTable: p,
                referencedColumns: [Identifier(raw: "id")]
            ))
        ])
        let result = LayoutEngine.layered(schema)
        let parentPos = result.positions.first { $0.node.normalized == "parent" }
        let childPos = result.positions.first { $0.node.normalized == "child" }
        XCTAssertNotNil(parentPos)
        XCTAssertNotNil(childPos)
        XCTAssertLessThan(parentPos!.y, childPos!.y)
    }
}
