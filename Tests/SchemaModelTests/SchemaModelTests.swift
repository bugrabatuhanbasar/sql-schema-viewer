import XCTest
@testable import SchemaModel

final class SchemaModelTests: XCTestCase {
    func testIdentifierUnquotedIsLowercased() {
        let id = Identifier(raw: "Users")
        XCTAssertEqual(id.normalized, "users")
    }

    func testIdentifierQuotedPreservesCase() {
        let id = Identifier(raw: "Users", quoted: true)
        XCTAssertEqual(id.normalized, "Users")
    }

    func testDataTypeIntegerCompatibility() {
        let a = DataType.named("bigint", params: [])
        let b = DataType.named("integer", params: [])
        XCTAssertTrue(a.isCompatible(with: b))
    }

    func testDataTypeIntTextIncompatible() {
        let a = DataType.named("int", params: [])
        let b = DataType.named("text", params: [])
        XCTAssertFalse(a.isCompatible(with: b))
    }

    func testSummaryMatchesSpecFormat() {
        var s = Schema(dialect: .postgres)
        s.stats = AnalysisStats(fullyParsedObjects: 30, partiallyParsedObjects: 3, skippedStatements: 4)
        s.tables[Identifier(raw: "a")] = Table(name: Identifier(raw: "a"))
        s.tables[Identifier(raw: "b")] = Table(name: Identifier(raw: "b"))
        _ = s.summarySentence
        // Contract: sentence contains the counts and the exact phrasing.
        XCTAssertTrue(s.summarySentence.contains("Fully parsed 30 objects"))
        XCTAssertTrue(s.summarySentence.contains("partially parsed 3 objects"))
        XCTAssertTrue(s.summarySentence.contains("skipped 4 unsupported statements"))
    }
}
