import XCTest
@testable import DependencyAnalyzer
import SchemaModel

final class DependencyAnalyzerTests: XCTestCase {
    func testForeignKeyEdge() {
        var s = Schema()
        let a = Identifier(raw: "a"), b = Identifier(raw: "b")
        s.tables[a] = Table(name: a)
        s.tables[b] = Table(name: b, constraints: [
            .foreignKey(ForeignKeySpec(localColumns: [Identifier(raw: "a_id")], referencedTable: a, referencedColumns: [Identifier(raw: "id")]))
        ])
        let g = DependencyAnalyzer.analyze(s)
        XCTAssertTrue(g.edges.contains(DependencyEdge(from: b, to: a, kind: .table, confidence: .complete)))
    }

    func testViewSelectFromCreatesEdge() {
        var s = Schema()
        let users = Identifier(raw: "users")
        let view = Identifier(raw: "active_users")
        s.tables[users] = Table(name: users)
        s.views[view] = View(
            name: view,
            definitionSQL: "CREATE VIEW active_users AS SELECT id, email FROM users WHERE active = true;",
            confidence: .partial
        )
        let g = DependencyAnalyzer.analyze(s)
        XCTAssertTrue(g.edges.contains { $0.from == view && $0.to == users && $0.confidence == .complete })
    }

    func testExecuteImmediateMarksReferenceAsPartial() {
        var s = Schema()
        let users = Identifier(raw: "users")
        let routine = Identifier(raw: "purge")
        s.tables[users] = Table(name: users)
        s.routines[routine] = Routine(
            name: routine, kind: .procedure,
            bodySQL: "BEGIN EXECUTE IMMEDIATE 'DELETE FROM users'; END;",
            confidence: .partial
        )
        let g = DependencyAnalyzer.analyze(s)
        XCTAssertTrue(g.edges.contains { $0.from == routine && $0.to == users && $0.confidence == .partial })
    }

    func testTriggerAnchoredToItsTable() {
        var s = Schema()
        let orders = Identifier(raw: "orders")
        let audit = Identifier(raw: "audit_log")
        let tr = Identifier(raw: "trg_order_audit")
        s.tables[orders] = Table(name: orders)
        s.tables[audit] = Table(name: audit)
        s.triggers[tr] = Trigger(
            name: tr, table: orders, timing: .after, events: [.insert],
            bodySQL: "BEGIN INSERT INTO audit_log SELECT * FROM orders; END;"
        )
        let g = DependencyAnalyzer.analyze(s)
        XCTAssertTrue(g.edges.contains { $0.from == tr && $0.to == orders && $0.kind == .table })
        XCTAssertTrue(g.edges.contains { $0.from == tr && $0.to == audit })
    }
}
