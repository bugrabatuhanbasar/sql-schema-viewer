import XCTest
@testable import DiagramRenderer
import LayoutEngine
import SchemaModel

final class RendererGoldenTests: XCTestCase {
    private func fixtureScene() -> DiagramScene {
        var s = Schema()
        let a = Identifier(raw: "a"), b = Identifier(raw: "b")
        s.tables[a] = Table(name: a, columns: [
            Column(name: Identifier(raw: "id"), type: .named("int", params: []), nullable: false)
        ])
        s.tables[b] = Table(name: b, columns: [
            Column(name: Identifier(raw: "id"), type: .named("int", params: []), nullable: false),
            Column(name: Identifier(raw: "a_id"), type: .named("int", params: []))
        ], constraints: [
            .foreignKey(ForeignKeySpec(localColumns: [Identifier(raw: "a_id")],
                                       referencedTable: a,
                                       referencedColumns: [Identifier(raw: "id")]))
        ])
        return DiagramRenderer.buildScene(s, layout: LayoutEngine.layout(s))
    }

    func testSVGContainsBothTables() {
        let svg = SVGExporter.export(fixtureScene())
        XCTAssertTrue(svg.contains("<svg"))
        XCTAssertTrue(svg.contains(">a<"))
        XCTAssertTrue(svg.contains(">b<"))
        XCTAssertTrue(svg.contains("id: int"))
    }

    func testSVGIsDeterministic() {
        let a = SVGExporter.export(fixtureScene())
        let b = SVGExporter.export(fixtureScene())
        XCTAssertEqual(a, b)
    }

    func testSVGEscapesHtml() {
        var scene = DiagramScene()
        scene.nodes.append(.init(rect: .init(x: 0, y: 0, width: 100, height: 50), title: "a<b>&\"c", lines: []))
        let svg = SVGExporter.export(scene)
        XCTAssertTrue(svg.contains("a&lt;b&gt;&amp;&quot;c"))
    }

    #if canImport(AppKit)
    func testPNGReturnsData() {
        let png = RasterExporter.png(fixtureScene())
        XCTAssertNotNil(png)
        XCTAssertGreaterThan(png?.count ?? 0, 100)
        // PNG magic
        let magic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        XCTAssertEqual(Array(png!.prefix(4)), magic)
    }

    func testPDFReturnsData() {
        let pdf = RasterExporter.pdf(fixtureScene())
        XCTAssertNotNil(pdf)
        // PDF magic "%PDF"
        XCTAssertEqual(Array(pdf!.prefix(4)), [0x25, 0x50, 0x44, 0x46])
    }
    #endif
}
